import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import test from "node:test";
import {
  githubPagesBasePath,
  githubPagesOrigin,
  githubPagesURL,
  validateGitHubPagesPublication,
} from "../lib/github-pages-publication.mjs";

const root = new URL("../", import.meta.url);
const output = new URL("out/", root);
const siteURL = githubPagesURL;
const basePath = githubPagesBasePath;

test("requires independent site approval while keeping the app release on hold", () => {
  const sitePublication = { state: "approved", siteURL: githubPagesOrigin };
  const releasePublication = { state: "holding", releaseURL: null };
  assert.deepEqual(validateGitHubPagesPublication(sitePublication, releasePublication), {
    basePath,
    origin: githubPagesOrigin,
    siteURL,
  });

  for (const [site, release] of [
    [{ state: "holding", siteURL: null }, releasePublication],
    [{ state: "approved", siteURL: "https://example.com" }, releasePublication],
    [sitePublication, { state: "published", releaseURL: "https://github.com/example/release" }],
    [sitePublication, { state: "holding", releaseURL: "https://github.com/example/release" }],
  ]) {
    assert.throws(() => validateGitHubPagesPublication(site, release));
  }
});

async function filesBelow(directory, prefix = "") {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    assert.equal(entry.isSymbolicLink(), false, "Pages output must not contain symbolic links");
    const relativePath = `${prefix}${entry.name}`;
    const entryURL = new URL(encodeURIComponent(entry.name) + (entry.isDirectory() ? "/" : ""), directory);
    if (entry.isDirectory()) files.push(...await filesBelow(entryURL, `${relativePath}/`));
    else files.push(relativePath);
  }
  return files;
}

test("exports the approved indexable holding site under the repository base path", async () => {
  const html = await readFile(new URL("index.html", output), "utf8");

  assert.match(html, new RegExp(`<link rel="canonical" href="${siteURL}"`));
  assert.match(html, new RegExp(`<meta property="og:url" content="${siteURL}"`));
  assert.doesNotMatch(html, /<meta name="robots" content="noindex/i);
  assert.match(html, /There is no supported public download today\./);
  assert.doesNotMatch(html, /releases\/tag\/v0\.1\.0/);
  assert.doesNotMatch(html, /Download the unsigned DMG and checksum/);

  const relativeAttributeURLs = [
    ...html.matchAll(/\b(?:content|href|poster|src)="(\/[^"\s]+)"/g),
  ].map((match) => match[1]);
  assert.ok(relativeAttributeURLs.length > 0, "the URL audit must inspect rendered attributes");
  assert.deepEqual(
    relativeAttributeURLs.filter((url) => !url.startsWith(`${basePath}/`)),
    [],
    "every root-relative rendered asset URL must carry the repository base path",
  );

  for (const assetPath of [
    "/app-icon.svg",
    "/og.png",
    "/screenshots/capture.png",
    "/gallery/01-capture.png",
    "/gallery/02-edit-display.png",
    "/gallery/03-edit-sound.png",
    "/gallery/04-review.png",
    "/demo/desk-setup-switcher.mp4",
    "/demo/captions.en.vtt",
    "/demo/captions.ko.vtt",
  ]) {
    assert.match(html, new RegExp(`${basePath}${assetPath.replaceAll("/", "\\/")}`));
    await access(new URL(assetPath.slice(1), output));
  }

  assert.match(html, new RegExp(`${basePath}/_next/`));
  await access(new URL(".nojekyll", output));
});

test("keeps the exported artifact static and free of deploy-time links", async () => {
  const files = await filesBelow(output);
  assert.ok(files.includes("index.html"));
  assert.ok(files.includes(".nojekyll"));
  assert.ok(files.some((path) => path.startsWith("_next/static/") && path.endsWith(".js")));
  assert.equal(files.some((path) => path.endsWith(".php") || path.endsWith(".rb")), false);
});
