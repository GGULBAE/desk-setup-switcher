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
The media gate also requires `ffmpeg`/`ffprobe`; CI installs the Homebrew
`ffmpeg@7` developer tool, then installs only the lockfile-pinned site dependency
graph with lifecycle scripts disabled, checks the registry advisory feed, and
runs that same command in a dedicated public-surface job. Neither Homebrew nor
FFmpeg is an application or site runtime dependency.

Copy `.env.example` to the gitignored `.env.local` and replace its placeholder
`NEXT_PUBLIC_SITE_URL` only after the final HTTPS origin has been approved in
[`site-publication.json`](site-publication.json). The build loads that file
without evaluating it as shell code. `npm run build` fails unless the record is
`approved` and `NEXT_PUBLIC_SITE_URL` is byte-for-byte equal to its exact clean
origin; missing, local, IP-literal, non-HTTPS, non-canonical,
reserved/placeholder, arbitrary, and mismatched origins all fail closed.
`npm run build:local` and `npm run verify` bypass the publication approval only
for explicit HTTP loopback origins used by local metadata checks; they still
strictly parse and validate the tracked record on every build.

`npm run verify` builds the Cloudflare Worker-compatible Sites output, lints the source, renders the page, checks the honest release/support copy and security headers, verifies that no cookie is set, scans application source and the built client for tracking/storage boundaries, and requires all public screenshots, video, and bilingual captions.

[`release-publication.json`](release-publication.json) is the site's only
rendering-state switch. It is schema-checked during every build. `holding` requires a null URL;
`published` accepts only the exact canonical `v0.1.0` GitHub Release URL. The
verification command renders and checks both states before rebuilding the
currently tracked state. If an intermediate state check fails, it still attempts
that restoration and removes `dist` if restoration cannot complete.

The overall public launch is deliberately broader than that one site-data
switch. The same public-surface gate cross-binds the release and site-origin
records and checks README, the English/Korean guide index and user guides,
PRIVACY, SUPPORT-MATRIX, `SECURITY.md`, `SUPPORT.md`, and lifecycle-neutral
support-form copy. The immutable Release body is self-contained and never
depends on a mutable branch document. After that Release is visibly public, the
locally pre-reviewed public-copy patch may be published for protected review;
its review tree and merged `master` tree must match, and both required CI jobs
must pass on the review head and exact final `master` SHA before deployment.
Component code is not rewritten during that transition.

[`site-publication.json`](site-publication.json) is a separate canonical-origin
approval record; it does not change release copy. Its exact three-key
`desk-setup-switcher.site-origin/v1` schema permits only `holding` with a null
`siteURL`, or `approved` with one exact clean public HTTPS origin. The strict
reader rejects duplicate or extra keys, malformed JSON, non-canonical UTF-8,
and linked files. Because the origin gate runs before the site build, only the
approved value can become the production canonical and Open Graph URL.

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
- Apple Silicon with a macOS 14 deployment target is the planned `v0.1.0` platform. At least one external exact-candidate lifecycle report must pass on Sonoma before that minimum-OS support claim is used; the `x86_64` slice is not advertised as physically verified.
- On 2026-07-20, current-source opt-in read-only tests passed Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths on Apple Silicon/macOS 26.5.2. They did not itemize actual ColorSync-profile, input-volume, or service-IPv4 field presence/read on this host, so those item-level claims and every apply/rollback path remain mock-only.
- Comprehensive assistive-technology certification is outside the initial beta gate. Keyboard behavior, accessibility names and values, and non-color state cues remain required.

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
