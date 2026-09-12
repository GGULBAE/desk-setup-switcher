import { spawn } from "node:child_process";
import { access, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { validateGitHubPagesPublication } from "../lib/github-pages-publication.mjs";
import { validateReleasePublicationFile } from "./verify-release-publication.mjs";
import { validateSitePublicationFile } from "./verify-site-origin.mjs";

const root = new URL("../", import.meta.url);
const output = new URL("out/", root);

const [sitePublication, releasePublication] = await Promise.all([
  validateSitePublicationFile(fileURLToPath(new URL("site-publication.json", root))),
  validateReleasePublicationFile(fileURLToPath(new URL("release-publication.json", root))),
]);

const pagesPublication = validateGitHubPagesPublication(sitePublication, releasePublication);

await rm(output, { force: true, recursive: true });

const environment = { ...process.env };
delete environment.ALLOW_LOCAL_SITE_ORIGIN;
delete environment.ALLOW_PRIVATE_SITE_ORIGIN;
delete environment.NEXT_PUBLIC_RELEASE_FIXTURE;
delete environment.NEXT_PUBLIC_SITE_AUDIENCE;
Object.assign(environment, {
  DESK_SETUP_GITHUB_PAGES: "1",
  NEXT_TELEMETRY_DISABLED: "1",
  NEXT_PUBLIC_SITE_BASE_PATH: pagesPublication.basePath,
  NEXT_PUBLIC_SITE_URL: sitePublication.siteURL,
});

const nextCLI = fileURLToPath(new URL("node_modules/next/dist/bin/next", root));
const exitCode = await new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [nextCLI, "build"], {
    cwd: root,
    env: environment,
    stdio: "inherit",
  });
  child.once("error", reject);
  child.once("exit", (code, signal) => {
    if (signal) {
      reject(new Error(`Next.js static export was interrupted by ${signal}`));
      return;
    }
    resolve(code ?? 1);
  });
});

if (exitCode !== 0) {
  throw new Error(`Next.js static export failed with exit code ${exitCode}`);
}

await access(new URL("index.html", output));
await writeFile(new URL(".nojekyll", output), "", { encoding: "utf8", mode: 0o644 });
