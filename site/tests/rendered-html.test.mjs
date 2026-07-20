import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { access, link, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { once } from "node:events";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = new URL("../", import.meta.url);
const originGatePath = fileURLToPath(new URL("scripts/verify-site-origin.mjs", root));
const originGateModule = await import(new URL("scripts/verify-site-origin.mjs", root));
const publicationModule = await import(new URL("lib/release-publication.mjs", root));
const publicationFileModule = await import(new URL("scripts/verify-release-publication.mjs", root));
const releaseCopyModule = await import(new URL("lib/release-copy.mjs", root));
const trackedPublication = await publicationFileModule.validateReleasePublicationFile(
  fileURLToPath(new URL("release-publication.json", root)),
);
const trackedState = trackedPublication.state;
const expectedReleaseState = process.env.EXPECTED_RELEASE_STATE === "current"
  ? trackedState
  : process.env.EXPECTED_RELEASE_STATE;

assert.match(expectedReleaseState ?? "", /^(holding|published)$/);

function runOriginGate(origin, { allowLocal = false, gatePath = originGatePath } = {}) {
  const env = { ...process.env };
  delete env.NEXT_PUBLIC_SITE_URL;
  delete env.ALLOW_LOCAL_SITE_ORIGIN;
  if (origin !== undefined) env.NEXT_PUBLIC_SITE_URL = origin;
  if (allowLocal) env.ALLOW_LOCAL_SITE_ORIGIN = "1";
  return spawnSync(process.execPath, [gatePath], {
    cwd: fileURLToPath(root),
    env,
    encoding: "utf8",
  });
}

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders the complete public-beta landing page without setting cookies", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("set-cookie"), null);
  assert.match(response.headers.get("content-security-policy") ?? "", /default-src 'self'/);
  assert.match(response.headers.get("content-security-policy") ?? "", /frame-ancestors 'none'/);
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.match(response.headers.get("permissions-policy") ?? "", /geolocation=\(\)/);

  const html = await response.text();
  assert.match(html, /<title>Desk Setup Switcher — Capture, review, and apply your desk settings<\/title>/i);
  assert.match(html, /<link rel="canonical" href="http:\/\/localhost:3000\/"\/>/i);
  assert.match(html, /<meta property="og:url" content="http:\/\/localhost:3000\/"\/>/i);
  assert.match(html, /Bring your desk back, deliberately\./);
  assert.match(html, /Capture/);
  assert.match(html, /Edit/);
  assert.match(html, /Review &amp; Apply/);
  assert.match(html, /No account/);
  assert.match(html, /No cloud/);
  assert.match(html, /No telemetry/);
  if (expectedReleaseState === "holding") {
    assert.match(html, /Open-source macOS public beta candidate/);
    assert.match(html, /There is no supported public download today\./);
    assert.match(html, /Planned v0\.1\.0 platform: Apple Silicon with a macOS 14 deployment target/);
    assert.match(html, /Exact-candidate lifecycle testing on Sonoma remains a release gate/);
    assert.match(html, /private vulnerability reporting must be enabled and tested before release/);
    assert.doesNotMatch(html, /releases\/tag\/v0\.1\.0/);
    assert.doesNotMatch(html, /v0\.1\.0 support: Apple Silicon on macOS 14 or later/);
  } else {
    assert.match(html, /Open-source macOS public beta<\/p>/);
    assert.doesNotMatch(html, /Open-source macOS public beta candidate/);
    assert.match(html, /Download v0\.1\.0/);
    assert.match(html, /href="https:\/\/github\.com\/GGULBAE\/desk-setup-switcher\/releases\/tag\/v0\.1\.0"/);
    assert.match(html, /Download the signed public beta\./);
    assert.match(html, /v0\.1\.0 support: Apple Silicon on macOS 14 or later/);
    assert.match(html, /private vulnerability reporting route in SECURITY\.md/);
    assert.doesNotMatch(html, /There is no supported public download today\./);
    assert.doesNotMatch(html, /Exact-candidate lifecycle testing on Sonoma remains a release gate/);
    assert.doesNotMatch(html, /private vulnerability reporting must be enabled and tested before release/);
  }
  assert.match(html, /Current-source group\/base live-read/);
  assert.match(html, /item-level read unclaimed/);
  assert.match(html, /apply\/rollback mock-only/);
  assert.match(html, /No live setting mutation has been hardware verified\./);
  assert.match(html, /Apply Available Settings/);
  assert.match(html, /Keep Changes/);
  assert.match(html, /Revert Now/);
  assert.match(html, /hosting provider still processes requests and may retain aggregate operational metrics/);
  assert.doesNotMatch(html, /VoiceOver/i);
  assert.match(html, /\/screenshots\/capture\.png/);
  assert.match(html, /\/screenshots\/edit\.png/);
  assert.match(html, /\/screenshots\/review\.png/);
  assert.match(html, /\/og\.png/);
  assert.match(html, /\/demo\/desk-setup-switcher\.mp4/);
  assert.match(html, /\/demo\/captions\.en\.vtt/);
  assert.match(html, /\/demo\/captions\.ko\.vtt/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape|react-loading-skeleton/i);
});

test("keeps the site account-free, local-content-only, and free of starter capabilities", async () => {
  const [page, landing, layout, worker, vite, buildPlugin, originGate, packageJson, hosting, builtWrangler] = await Promise.all([
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/landing-page.tsx", root), "utf8"),
    readFile(new URL("app/layout.tsx", root), "utf8"),
    readFile(new URL("worker/index.ts", root), "utf8"),
    readFile(new URL("vite.config.ts", root), "utf8"),
    readFile(new URL("build/sites-vite-plugin.ts", root), "utf8"),
    readFile(new URL("scripts/verify-site-origin.mjs", root), "utf8"),
    readFile(new URL("package.json", root), "utf8"),
    readFile(new URL(".openai/hosting.json", root), "utf8"),
    readFile(new URL("dist/server/wrangler.json", root), "utf8"),
  ]);
  const browserSource = `${page}\n${landing}\n${layout}`;
  const runtimeSource = `${worker}\n${vite}\n${buildPlugin}`;
  const clientAssetDirectory = new URL("dist/client/assets/", root);
  const clientJavaScript = (
    await Promise.all(
      (await readdir(clientAssetDirectory))
        .filter((name) => name.endsWith(".js"))
        .map((name) => readFile(new URL(name, clientAssetDirectory), "utf8")),
    )
  ).join("\n");

  assert.match(page, /force-static/);
  assert.deepEqual(JSON.parse(hosting), { d1: null, r2: null });
  const wrangler = JSON.parse(builtWrangler);
  assert.equal(wrangler.observability?.enabled, false);
  assert.deepEqual(wrangler.assets, { directory: "../client" });
  assert.deepEqual(wrangler.vars, {});

  const emptyArrayBindingKeys = [
    "agent_memory",
    "ai_search",
    "ai_search_namespaces",
    "analytics_engine_datasets",
    "artifacts",
    "d1_databases",
    "dispatch_namespaces",
    "flagship",
    "hyperdrive",
    "kv_namespaces",
    "migrations",
    "mtls_certificates",
    "pipelines",
    "r2_buckets",
    "ratelimits",
    "secrets_store_secrets",
    "send_email",
    "services",
    "unsafe_hello_world",
    "vectorize",
    "vpc_networks",
    "vpc_services",
    "worker_loaders",
    "workflows",
  ];
  for (const key of emptyArrayBindingKeys) {
    assert.deepEqual(wrangler[key], [], `expected no ${key} binding`);
  }
  for (const key of ["cloudchamber", "define", "exports", "triggers"]) {
    assert.deepEqual(wrangler[key], {}, `expected empty ${key} configuration`);
  }
  assert.deepEqual(wrangler.durable_objects, { bindings: [] });
  assert.deepEqual(wrangler.logfwdr, { bindings: [] });
  assert.deepEqual(wrangler.queues, { producers: [], consumers: [] });

  const reviewedWranglerKeys = new Set([
    ...emptyArrayBindingKeys,
    "assets",
    "build",
    "cloudchamber",
    "compatibility_date",
    "compatibility_flags",
    "define",
    "dev",
    "durable_objects",
    "exports",
    "jsx_factory",
    "jsx_fragment",
    "logfwdr",
    "main",
    "name",
    "no_bundle",
    "observability",
    "python_modules",
    "queues",
    "rules",
    "topLevelName",
    "triggers",
    "vars",
  ]);
  assert.deepEqual(
    Object.keys(wrangler).filter((key) => !reviewedWranglerKeys.has(key)).sort(),
    [],
    "new Wrangler configuration keys require an explicit privacy/binding review",
  );
  assert.doesNotMatch(
    browserSource,
    /\bfetch\s*\(|XMLHttpRequest|sendBeacon|document\.cookie|localStorage|sessionStorage|gtag\s*\(|mixpanel|segment\.io/i,
  );
  assert.doesNotMatch(browserSource, /<script[^>]+src=["']https?:\/\//i);
  assert.match(landing, /내 책상 설정을, 내가 확인하고 되돌립니다/);
  assert.match(landing, /텔레메트리 없음/);
  assert.match(landing, /homeLabel: "Desk Setup Switcher 홈"/);
  assert.match(landing, /aria-label=\{text\.homeLabel\}/);
  assert.match(landing, /userGuidePath: "docs\/guides\/USER-GUIDE\.md"/);
  assert.match(landing, /userGuidePath: "docs\/guides\/USER-GUIDE\.ko\.md"/);
  assert.match(landing, /href=\{`\$\{repositoryURL\}\/blob\/master\/\$\{text\.userGuidePath\}`\}/);
  assert.doesNotMatch(landing, /VoiceOver/i);
  assert.doesNotMatch(
    runtimeSource,
    /D1Database|r2_buckets|d1_databases|handleImageOptimization|\bIMAGES\b|drizzle/i,
  );
  assert.doesNotMatch(packageJson, /drizzle|react-loading-skeleton/);
  assert.doesNotMatch(
    clientJavaScript,
    /document\.cookie|localStorage|indexedDB|sendBeacon|gtag\s*\(|mixpanel|segment\.io/i,
  );
  assert.match(clientJavaScript, /__vinext_rsc_initial_reload__/);
  assert.match(clientJavaScript, /__vinext_hard_navigation_target__/);
  const allowedSessionStorageKeys = [
    "__vinext_hard_navigation_target__",
    "__vinext_rsc_initial_reload__",
  ];
  const discoveredSessionStorageKeys = [
    ...new Set(clientJavaScript.match(/__vinext_[a-z0-9_]+__/g) ?? []),
  ].sort();
  assert.deepEqual(discoveredSessionStorageKeys, allowedSessionStorageKeys);
  assert.doesNotMatch(clientJavaScript, /sessionStorage\s*\[/);

  const storageKeyAliases = new Map(
    [...clientJavaScript.matchAll(/(?:\bvar\s+|,)([$A-Z_a-z][$\w]*)=`(__vinext_[a-z0-9_]+__)`/g)]
      .map((match) => [match[1], match[2]]),
  );
  const sessionStorageCalls = [
    ...clientJavaScript.matchAll(
      /(?:window\.)?sessionStorage\.(getItem|setItem|removeItem)\(([$A-Z_a-z][$\w]*)/g,
    ),
  ];
  assert.equal(sessionStorageCalls.length, 7);
  assert.deepEqual(
    [...new Set(sessionStorageCalls.map((match) => storageKeyAliases.get(match[2])))].sort(),
    allowedSessionStorageKeys,
    "every sessionStorage call must resolve to one of the two reviewed vinext guards",
  );
  assert.equal(
    clientJavaScript.match(/\bsessionStorage\b/g)?.length,
    9,
    "only seven reviewed calls and two framework error messages may mention sessionStorage",
  );
  assert.match(packageJson, /verify-site-origin\.mjs/);
  assert.match(originGate, /public site origin must use HTTPS/i);
  assert.match(originGate, /placeholder NEXT_PUBLIC_SITE_URL/i);

  await Promise.all([
    assert.rejects(access(new URL("app/_sites-preview", root))),
    assert.rejects(access(new URL("app/chatgpt-auth.ts", root))),
    assert.rejects(access(new URL("db", root))),
    assert.rejects(access(new URL("drizzle.config.ts", root))),
    assert.rejects(access(new URL("examples", root))),
  ]);
});

test("ships three sanitized screens and bilingual caption files", async () => {
  const assets = [
    "public/screenshots/capture.png",
    "public/screenshots/edit.png",
    "public/screenshots/review.png",
    "public/og.png",
    "public/demo/desk-setup-switcher.mp4",
    "public/demo/captions.en.vtt",
    "public/demo/captions.ko.vtt",
  ];
  await Promise.all(assets.map((asset) => access(new URL(asset, root))));

  const [english, korean] = await Promise.all([
    readFile(new URL("public/demo/captions.en.vtt", root), "utf8"),
    readFile(new URL("public/demo/captions.ko.vtt", root), "utf8"),
  ]);
  assert.match(english, /Capture — Read current settings/);
  assert.match(english, /Review & Apply/);
  assert.match(korean, /Capture — 현재 설정을 읽습니다/);
  assert.match(korean, /Review & Apply/);
});

test("site origin approval fails closed and narrowly allows explicit local builds", async () => {
  const rejected = [
    undefined,
    "http://desksetup.app",
    "http://localhost:3000",
    "https://localhost",
    "https://localhost.",
    "https://127.0.0.1",
    "https://127.1",
    "https://0.0.0.0",
    "https://[::1]",
    "https://[::]",
    "https://[::ffff:7f00:1]",
    "https://desk-setup-switcher.invalid",
    "https://desk-setup-switcher.invalid.",
    "https://example",
    "https://foo.example",
    "https://desksetup.test",
    "https://router.local",
    "https://desksetup.app/path",
    "https://desksetup.app?source=test",
    "https://user:password@desksetup.app",
  ];
  for (const origin of rejected) {
    const result = runOriginGate(origin);
    assert.notEqual(result.status, 0, `expected origin gate to reject ${origin ?? "missing origin"}`);
  }

  for (const origin of [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://[::1]:3000",
  ]) {
    assert.equal(
      runOriginGate(origin, { allowLocal: true }).status,
      0,
      `expected explicit local build to allow ${origin}`,
    );
  }

  assert.notEqual(runOriginGate("https://localhost", { allowLocal: true }).status, 0);
  assert.notEqual(runOriginGate("https://desksetup.app", { allowLocal: true }).status, 0);

  const trackedApproval = await originGateModule.validateSitePublicationFile(
    fileURLToPath(new URL("site-publication.json", root)),
  );
  assert.deepEqual(trackedApproval, {
    schemaVersion: "desk-setup-switcher.site-origin/v1",
    state: "holding",
    siteURL: null,
  });
  assert.notEqual(runOriginGate("https://desksetup.app").status, 0);
  const buildScript = JSON.parse(await readFile(new URL("package.json", root), "utf8")).scripts.build;
  assert.ok(
    buildScript.indexOf("verify-site-origin.mjs") < buildScript.indexOf("node_modules/vinext"),
    "the approved-origin gate must run before the renderer consumes NEXT_PUBLIC_SITE_URL",
  );

  const temporaryDirectory = await mkdtemp(join(tmpdir(), "desk-setup-site-origin-"));
  const scriptsDirectory = join(temporaryDirectory, "scripts");
  const fixtureGatePath = join(scriptsDirectory, "verify-site-origin.mjs");
  const fixturePublicationPath = join(temporaryDirectory, "site-publication.json");
  try {
    await mkdir(scriptsDirectory, { recursive: true });
    await writeFile(fixtureGatePath, await readFile(originGatePath, "utf8"), {
      encoding: "utf8",
      mode: 0o600,
    });

    const approved = {
      schemaVersion: "desk-setup-switcher.site-origin/v1",
      state: "approved",
      siteURL: "https://desksetup.app",
    };
    await writeFile(fixturePublicationPath, `${JSON.stringify(approved)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    assert.equal(
      runOriginGate("https://desksetup.app", { gatePath: fixtureGatePath }).status,
      0,
    );
    for (const origin of [
      "https://otherdesk.app",
      "https://desksetup.app/",
      "https://DESKSETUP.app",
    ]) {
      assert.notEqual(
        runOriginGate(origin, { gatePath: fixtureGatePath }).status,
        0,
        `expected approved-origin gate to reject ${origin}`,
      );
    }

    const malformedRecords = [
      "{not-json}\n",
      '{"schemaVersion":"desk-setup-switcher.site-origin/v1","state":"holding","state":"approved","siteURL":"https://desksetup.app"}\n',
      `${JSON.stringify({ ...approved, extra: true })}\n`,
      `${JSON.stringify({ ...approved, siteURL: "https://desksetup.app/" })}\n`,
      `${JSON.stringify({ ...approved, siteURL: "https://desk-setup-switcher.invalid" })}\n`,
      `${JSON.stringify({ ...approved, state: "holding" })}\n`,
    ];
    for (const source of malformedRecords) {
      await writeFile(fixturePublicationPath, source, { encoding: "utf8", mode: 0o600 });
      assert.notEqual(
        runOriginGate("https://desksetup.app", { gatePath: fixtureGatePath }).status,
        0,
        `expected site publication record to fail: ${source}`,
      );
    }
    assert.notEqual(
      runOriginGate("http://localhost:3000", {
        allowLocal: true,
        gatePath: fixtureGatePath,
      }).status,
      0,
      "local builds must still strictly validate the tracked site publication record",
    );

    await writeFile(fixturePublicationPath, `${JSON.stringify(approved)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    const symlinkPath = join(temporaryDirectory, "site-publication-symlink.json");
    const hardlinkPath = join(temporaryDirectory, "site-publication-hardlink.json");
    await symlink(fixturePublicationPath, symlinkPath);
    await assert.rejects(originGateModule.validateSitePublicationFile(symlinkPath));
    await link(fixturePublicationPath, hardlinkPath);
    await assert.rejects(originGateModule.validateSitePublicationFile(hardlinkPath));
  } finally {
    await rm(temporaryDirectory, { force: true, recursive: true });
  }
});

test("release publication metadata fails closed and pins the canonical release", async () => {
  const [holding, published] = await Promise.all([
    readFile(new URL("tests/fixtures/release-holding.json", root), "utf8").then(JSON.parse),
    readFile(new URL("tests/fixtures/release-published.json", root), "utf8").then(JSON.parse),
  ]);
  const validate = publicationModule.validateReleasePublication;
  const canonicalURL = publicationModule.canonicalReleaseURL;

  assert.equal(validate(holding).releaseURL, null);
  assert.equal(validate(published).releaseURL, canonicalURL);
  assert.equal(validate(trackedPublication).state, trackedState);

  const rejected = [
    null,
    [],
    { ...holding, extra: true },
    { ...holding, releaseURL: canonicalURL },
    { ...published, releaseURL: `${canonicalURL}/` },
    { ...published, releaseURL: "https://example.com/v0.1.0" },
    { ...published, state: "ready" },
    { ...published, version: "0.1.1" },
    { ...published, tag: "v0.1.1" },
    { ...published, schemaVersion: "desk-setup-switcher.site-release/v2" },
  ];
  for (const value of rejected) {
    assert.throws(() => validate(value));
  }

  const temporaryDirectory = await mkdtemp(join(tmpdir(), "desk-setup-site-release-"));
  try {
    const duplicatePath = join(temporaryDirectory, "duplicate.json");
    await writeFile(
      duplicatePath,
      '{"schemaVersion":"desk-setup-switcher.site-release/v1","state":"holding","state":"published","version":"0.1.0","tag":"v0.1.0","releaseURL":null}\n',
      { encoding: "utf8", mode: 0o600 },
    );
    await assert.rejects(publicationFileModule.validateReleasePublicationFile(duplicatePath));

    const validPath = join(temporaryDirectory, "valid.json");
    const symlinkPath = join(temporaryDirectory, "symlink.json");
    const hardlinkPath = join(temporaryDirectory, "hardlink.json");
    await writeFile(validPath, `${JSON.stringify(holding)}\n`, { encoding: "utf8", mode: 0o600 });
    await symlink(validPath, symlinkPath);
    await assert.rejects(publicationFileModule.validateReleasePublicationFile(symlinkPath));
    await link(validPath, hardlinkPath);
    await assert.rejects(publicationFileModule.validateReleasePublicationFile(hardlinkPath));
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("release holding and published copy stays bilingual", () => {
  const releasePresentation = releaseCopyModule.releasePresentation;
  const englishHolding = releasePresentation("en", false);
  const englishPublished = releasePresentation("en", true);
  const koreanHolding = releasePresentation("ko", false);
  const koreanPublished = releasePresentation("ko", true);

  assert.equal(englishHolding.eyebrow, "Open-source macOS public beta candidate");
  assert.equal(englishPublished.eyebrow, "Open-source macOS public beta");
  assert.match(englishHolding.actionLabel, /complete release gate passes/);
  assert.equal(englishPublished.actionLabel, "Download v0.1.0");
  assert.equal(englishHolding.installTitle, "A trusted download, once the gate passes.");
  assert.equal(englishPublished.installTitle, "Download the signed public beta.");
  assert.match(englishHolding.installBody, /There is no supported public download today\./);
  assert.match(englishPublished.installBody, /canonical GitHub Release/);
  assert.match(englishHolding.supportNote, /lifecycle testing on Sonoma remains a release gate/);
  assert.match(englishPublished.supportNote, /v0\.1\.0 support: Apple Silicon on macOS 14 or later/);
  assert.doesNotMatch(englishPublished.supportNote, /planned|remains a release gate/i);
  assert.match(englishHolding.contributeBody, /private vulnerability reporting must be enabled and tested before release/);
  assert.match(englishPublished.contributeBody, /private vulnerability reporting route in SECURITY\.md/);
  assert.doesNotMatch(englishPublished.contributeBody, /must be enabled|before release/i);
  assert.equal(koreanHolding.eyebrow, "오픈소스 macOS 공개 베타 후보");
  assert.equal(koreanPublished.eyebrow, "오픈소스 macOS 공개 베타");
  assert.match(koreanHolding.actionLabel, /릴리스 관문을 통과한 뒤/);
  assert.equal(koreanPublished.actionLabel, "v0.1.0 다운로드");
  assert.equal(koreanHolding.installTitle, "검증 관문을 통과한 다운로드만 제공합니다.");
  assert.equal(koreanPublished.installTitle, "서명된 public beta를 다운로드하세요.");
  assert.match(koreanHolding.installBody, /현재 지원되는 공개 다운로드는 없습니다\./);
  assert.match(koreanPublished.installBody, /공식 GitHub Release에서만 제공합니다\./);
  assert.match(koreanHolding.supportNote, /수명주기 검증을 통과해야 출시/);
  assert.match(koreanPublished.supportNote, /v0\.1\.0 지원 환경: Apple Silicon 기반 macOS 14 이상/);
  assert.doesNotMatch(koreanPublished.supportNote, /예정 환경|통과해야 출시/);
  assert.match(koreanHolding.contributeBody, /비공개 취약점 신고 기능은 출시 전에 활성화하고 검증/);
  assert.match(koreanPublished.contributeBody, /SECURITY\.md의 비공개 취약점 신고 경로/);
  assert.doesNotMatch(koreanPublished.contributeBody, /출시 전에 활성화/);
  assert.throws(() => releasePresentation("ja", false));
  assert.throws(() => releasePresentation("ko", "published"));
});

async function makeVerifierFixture(mode) {
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "desk-setup-site-verifier-"));
  const siteDirectory = join(temporaryDirectory, "site");
  const scriptsDirectory = join(siteDirectory, "scripts");
  await mkdir(scriptsDirectory, { recursive: true });
  await writeFile(
    join(scriptsDirectory, "verify-site.mjs"),
    await readFile(new URL("scripts/verify-site.mjs", root), "utf8"),
    { encoding: "utf8", mode: 0o600 },
  );
  const mockNPM = join(temporaryDirectory, "mock-npm.mjs");
  await writeFile(
    mockNPM,
    `import { appendFile, mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
const name = process.argv[3];
const dist = join(process.cwd(), "dist");
await appendFile(join(process.cwd(), "calls.txt"), name + "\\n");
if (name.startsWith("build:")) {
  await rm(dist, { force: true, recursive: true });
  await mkdir(dist, { recursive: true });
  await writeFile(join(dist, "state.txt"), name === "build:local" ? "current\\n" : name.replace("build:test-", "") + "\\n");
}
if (process.env.VERIFIER_MODE === "interrupt" && name === "test:published") {
  await writeFile(join(process.cwd(), "interrupt-ready"), "ready\\n");
  await new Promise((resolve) => setTimeout(resolve, 3_600_000));
}
if (process.env.VERIFIER_MODE === "test-failure" && name === "test:published") process.exit(9);
if (process.env.VERIFIER_MODE === "restore-failure" && name === "build:local") process.exit(10);
`,
    { encoding: "utf8", mode: 0o600 },
  );
  return {
    temporaryDirectory,
    siteDirectory,
    verifier: join(scriptsDirectory, "verify-site.mjs"),
    env: { ...process.env, npm_execpath: mockNPM, VERIFIER_MODE: mode },
  };
}

async function withTimeout(promise, milliseconds) {
  let timer;
  const { promise: timeout, reject } = Promise.withResolvers();
  timer = setTimeout(() => reject(new Error("Timed out waiting for verifier fixture")), milliseconds);
  timer.unref();
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

test("site verifier restores current output after a synthetic-state failure", async () => {
  const fixture = await makeVerifierFixture("test-failure");
  try {
    const result = spawnSync(process.execPath, [fixture.verifier], {
      cwd: fixture.siteDirectory,
      env: fixture.env,
      encoding: "utf8",
    });
    assert.equal(result.status, 1);
    assert.equal(await readFile(join(fixture.siteDirectory, "dist/state.txt"), "utf8"), "current\n");
  } finally {
    await rm(fixture.temporaryDirectory, { force: true, recursive: true });
  }
});

test("site verifier removes output when tracked-state restoration fails", async () => {
  const fixture = await makeVerifierFixture("restore-failure");
  try {
    const result = spawnSync(process.execPath, [fixture.verifier], {
      cwd: fixture.siteDirectory,
      env: fixture.env,
      encoding: "utf8",
    });
    assert.equal(result.status, 1);
    await assert.rejects(access(join(fixture.siteDirectory, "dist")));
  } finally {
    await rm(fixture.temporaryDirectory, { force: true, recursive: true });
  }
});

test("site verifier restores current output before preserving an interrupt status", { timeout: 10_000 }, async () => {
  const fixture = await makeVerifierFixture("interrupt");
  let child;
  let exitPromise;
  try {
    child = spawn(process.execPath, [fixture.verifier], {
      cwd: fixture.siteDirectory,
      detached: true,
      env: fixture.env,
      stdio: "ignore",
    });
    exitPromise = once(child, "exit");
    const readyPath = join(fixture.siteDirectory, "interrupt-ready");
    for (let attempts = 0; attempts < 100; attempts += 1) {
      try {
        await access(readyPath);
        break;
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
    }
    await access(readyPath);
    process.kill(-child.pid, "SIGTERM");
    const [code, signal] = await withTimeout(exitPromise, 8_000);
    assert.equal(signal, null);
    assert.equal(code, 143);
    assert.equal(await readFile(join(fixture.siteDirectory, "dist/state.txt"), "utf8"), "current\n");
  } finally {
    if (child?.pid) {
      try {
        process.kill(-child.pid, "SIGKILL");
      } catch (error) {
        if (error?.code !== "ESRCH") throw error;
      }
      if (child.exitCode === null && child.signalCode === null && exitPromise) {
        try {
          await withTimeout(exitPromise, 1_000);
        } catch {
          // The process group has already received SIGKILL; cleanup must continue.
        }
      }
    }
    await rm(fixture.temporaryDirectory, { force: true, recursive: true });
  }
});
