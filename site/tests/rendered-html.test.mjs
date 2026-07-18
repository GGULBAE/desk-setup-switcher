import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = new URL("../", import.meta.url);
const originGatePath = fileURLToPath(new URL("scripts/verify-site-origin.mjs", root));

function runOriginGate(origin, { allowLocal = false } = {}) {
  const env = { ...process.env };
  delete env.NEXT_PUBLIC_SITE_URL;
  delete env.ALLOW_LOCAL_SITE_ORIGIN;
  if (origin !== undefined) env.NEXT_PUBLIC_SITE_URL = origin;
  if (allowLocal) env.ALLOW_LOCAL_SITE_ORIGIN = "1";
  return spawnSync(process.execPath, [originGatePath], {
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
  assert.match(html, /Bring your desk back, deliberately\./);
  assert.match(html, /Capture/);
  assert.match(html, /Edit/);
  assert.match(html, /Review &amp; Apply/);
  assert.match(html, /No account/);
  assert.match(html, /No cloud/);
  assert.match(html, /No telemetry/);
  assert.match(html, /There is no supported public download today\./);
  assert.match(html, /Apple Silicon on macOS 14 or later/);
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

test("rejects non-public production origins and narrowly allows explicit local builds", () => {
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
  assert.equal(runOriginGate("https://desksetup.app").status, 0);
});
