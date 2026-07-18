# Desk Setup Switcher site

This directory contains the account-free, bilingual, single-page public site for Desk Setup Switcher. It has no account, database, object storage, project-set cookies, project analytics, telemetry, advertising, or remotely loaded third-party runtime content.

The site is release-preparation source. Do not deploy it publicly until the protected `v0.1.0` release candidate, canonical download URL, clean-install evidence, and maintainer publication approval are complete.

## Local development

Requires Node.js 22.13 or later.

```sh
npm ci --ignore-scripts
npm run dev
npm run verify
```

From the repository root, `make verify-public-surface` runs the site build,
lint, rendered-output/privacy tests, and the complete public/source asset gate.
CI installs only the lockfile-pinned dependency graph with lifecycle scripts
disabled, checks the registry advisory feed, then runs that same command in a
dedicated public-surface job.

Copy `.env.example` to the gitignored `.env.local` and replace its placeholder
`NEXT_PUBLIC_SITE_URL` with the final HTTPS origin before an approved
deployment. The build loads that file without evaluating it as shell code.
`npm run build` fails when the origin is missing, local, IP-literal,
non-HTTPS, non-canonical, reserved/placeholder, or not a fully qualified DNS
name. `npm run build:local` and `npm run verify` opt into exact HTTP loopback
origins only for local metadata checks.

`npm run verify` builds the Cloudflare Worker-compatible Sites output, lints the source, renders the page, checks the honest release/support copy and security headers, verifies that no cookie is set, scans application source and the built client for tracking/storage boundaries, and requires all public screenshots, video, and bilingual captions.

The application-authored site code does not persist product or visitor data in
browser storage. The bundled vinext router contains two framework-owned,
tab-scoped `sessionStorage` navigation guards named
`__vinext_rsc_initial_reload__` and `__vinext_hard_navigation_target__`. They may
briefly store only the current path or hard-navigation target to prevent reload
loops, then remove it. The verification test pins those two keys and seven
get/set/remove calls, and rejects other browser-storage or tracking APIs in the
built client.

`npm run audit:dependencies` is the networked dependency advisory gate. It is
kept separate from the deterministic local build and test command; the
2026-07-18 lockfile audit reports zero known vulnerabilities.

## Content boundaries

- The three product screens use synthetic fixture data and sanitized public derivatives.
- The silent demo stops at the Apply Preview. It does not simulate an Apply result or claim live hardware mutation.
- Download remains unavailable until the complete distribution gate passes and the maintainer-approved canonical GitHub Release exists.
- Apple Silicon on macOS 14 or later is the initial support claim; the `x86_64` slice is not advertised as physically verified.
- Read-only discovery and deterministic mock apply/rollback evidence are distinguished explicitly.
- Comprehensive assistive-technology certification is outside the initial beta gate.

Asset sources and sanitization are recorded in [release asset provenance](../docs/RELEASE-ASSET-PROVENANCE.md).

## Hosting

`.openai/hosting.json` deliberately declares no D1 or R2 capability, and the
built Worker disables request logs/traces with `observability.enabled: false`.
Cloudflare nevertheless provides built-in aggregate Worker request metrics as
hosting-platform behavior; those are not project product analytics. The public
site discloses this boundary. See Cloudflare's
[Workers metrics documentation](https://developers.cloudflare.com/workers/observability/metrics-and-analytics/)
and [privacy policy](https://www.cloudflare.com/privacypolicy/). Public
deployment, domain configuration, final Open Graph URL, and release-link
activation occur only after the user approves publication.
