# Desk Setup Switcher site

This directory contains the account-free, bilingual, single-page public site for Desk Setup Switcher. It has no account, database, object storage, project-set cookies, project analytics, telemetry, advertising, or remotely loaded third-party runtime content.

The maintainer approved the informational **holding** page for public GitHub
Pages hosting at <https://ggulbae.github.io/desk-setup-switcher/>. That approval
does not publish the app: `release-publication.json` remains `holding`, so the
page exposes no supported download or installation instructions. The exact
unsigned `v0.1.0` release candidate, canonical download URL and SHA-256,
clean-install/Open-Anyway evidence, and separate release-publication approval
are still required before download copy can appear.

The earlier owner-only internal preview is a separate path.
`private-preview.json` binds it to one registered Sites project and clean HTTPS
origin. `npm run build:private-preview` emits `noindex`, `nofollow`, and
`noimageindex` metadata and does not enable download copy or authorize an app
release. It is not the GitHub Pages deployment source.

## Local development

Requires Node.js 22.13 or later.

```sh
npm ci --ignore-scripts
npm run dev
npm run verify
npm run build:pages
```

From the repository root, `make verify-public-surface` runs the site build,
lint, rendered-output/privacy tests, and the complete public/source asset gate.
The Sites packaging plugin at `build/sites-vite-plugin.ts` is source despite its
directory name, so it is deliberately tracked; the gate rejects a missing,
untracked, or ignored copy to keep clean checkouts equivalent to local builds.
The media gate also requires `ffmpeg`/`ffprobe`; CI installs the Homebrew
`ffmpeg@7` developer tool, then installs only the lockfile-pinned site dependency
graph with lifecycle scripts disabled, checks the registry advisory feed, and
runs that same command in a dedicated public-surface job. Neither Homebrew nor
FFmpeg is an application or site runtime dependency.

Copy `.env.example` to the gitignored `.env.local` only for an explicitly
approved non-Pages production build. The general build loads
[`site-publication.json`](site-publication.json) without evaluating it as shell
code and fails closed on missing, local, IP-literal, non-HTTPS, non-canonical,
reserved/placeholder, arbitrary, or mismatched origins. `npm run build:local`
and `npm run verify` permit only explicit HTTP loopback origins for local
metadata checks; they still strictly parse the tracked publication record.

`npm run build:pages` is the dedicated public-hosting path. It fixes the clean
origin to `https://ggulbae.github.io`, the project base path to
`/desk-setup-switcher`, and emits a static artifact under `out/` with a
top-level `index.html` and `.nojekyll`. Assets, canonical/Open Graph metadata,
and internal navigation must retain that project path. The command must not
accept an arbitrary deployment URL from an untrusted workflow input.

`npm run verify` builds the Worker-compatible owner-preview output and the
GitHub Pages static output, lints the source, renders the page, checks the honest
release/support copy and applicable hosting boundaries, verifies that project
code sets no cookie, scans application source and built clients for
tracking/storage boundaries, and verifies the retained public-media inventory.

[`release-publication.json`](release-publication.json) is the site's only
rendering-state switch. It is schema-checked during every build. `holding` requires a null URL;
`published` accepts only the exact canonical `v0.1.0` GitHub Release URL. The
verification command renders and checks both states before rebuilding the
currently tracked state. If an intermediate state check fails, it still attempts
that restoration and removes `dist` if restoration cannot complete.

Public hosting of the holding page is deliberately independent from the app
release switch. The same public-surface gate checks README, the English/Korean
guide index and user guides, PRIVACY, SUPPORT-MATRIX, `SECURITY.md`,
`SUPPORT.md`, and lifecycle-neutral support-form copy so a public page cannot
imply that a download exists. The later immutable Release body remains
self-contained and never depends on a mutable branch document. When the app is
actually approved, a separately reviewed public-copy patch changes
`release-publication.json` and the bounded release documents without treating
this earlier Pages publication as release evidence.

[`site-publication.json`](site-publication.json) is the strict canonical-origin
record used by general production builds; it does not change release copy. Its
exact three-key `desk-setup-switcher.site-origin/v1` schema permits only
`holding` with a null `siteURL`, or `approved` with one exact clean public HTTPS
origin. The strict reader rejects duplicate or extra keys, malformed JSON,
non-canonical UTF-8, and linked files. The Pages builder additionally fixes and
validates the `/desk-setup-switcher` project base path before composing the
canonical and Open Graph URL.

The application-authored site code does not persist product or visitor data in
browser storage. The bundled vinext router contains two framework-owned,
tab-scoped `sessionStorage` navigation guards named
`__vinext_rsc_initial_reload__` and `__vinext_hard_navigation_target__`. They may
briefly store only the current path or hard-navigation target to prevent reload
loops, then remove it. The verification test pins those two keys and seven
get/set/remove calls, and rejects other browser-storage or tracking APIs in the
built client.

`npm run audit:dependencies` is the networked dependency advisory gate. It is
kept separate from the deterministic local build and test command. The
2026-09-08 refresh updates the pinned Vinext/RSC pair and vulnerable transitive
packages. The 2026-09-10 advisory follow-up pins Next.js and its ESLint config
to 16.3.4 and overrides every Sharp path to 0.35.4 while retaining the existing
React, Cloudflare/Wrangler, PostCSS, and Undici pins. `npm ci --ignore-scripts &&
npm audit` reports zero registry advisories. Vinext still bundles unpatched
`image-size` 2.0.2 in its
build tools; an empty audit report is not proof that the parser was fixed.
This site has no upload or image-optimization endpoint. Deployment-output
tests reject the parser in client/Worker chunks and inspect all nested
JavaScript chunks, refusing symlinks and empty output. Keep build inputs
reviewed. See the [original refresh](../docs/SITE-DEPENDENCY-REFRESH-2026-09-08.md)
and [current advisory follow-up](../docs/SITE-DEPENDENCY-REFRESH-2026-09-10.md).

## Content boundaries

- The page presents the current seven-setting Display/Sound scope: main display, resolution, output device/volume/mute, and input device/volume. Network and other legacy values remain dormant compatibility data, not current site capabilities.
- The rendered page presents a four-screen synthetic Capture, Edit Display, Edit Sound, and Review gallery plus a short silent walkthrough. The video requires an explicit user action, exposes English and Korean caption tracks and a visible transcript summary, and does not simulate Apply or a successful hardware change. Gallery and demo assets must remain tied to the current source and verified provenance before public publication.
- Download remains unavailable until the unsigned distribution gate passes and the maintainer-approved canonical GitHub Release exists. Published copy identifies the DMG as Developer ID-unsigned and not notarized, requires SHA-256 verification, and permits only the one-time macOS **Open Anyway** path without disabling Gatekeeper or removing quarantine.
- Apple Silicon with a macOS 14 deployment target is the planned `v0.1.0` platform. At least one external exact-candidate lifecycle report must pass on Sonoma before that minimum-OS support claim is used; the `x86_64` slice is not advertised as physically verified.
- On 2026-07-20, current-source opt-in read-only tests passed relevant source-group paths on Apple Silicon/macOS 26.5.2. This is read evidence, not proof of every individual field or any live Apply/rollback path; those mutation paths remain mock-only.
- Comprehensive assistive-technology certification is outside the initial beta gate. Keyboard behavior, accessibility names and values, and non-color state cues remain required.

Asset sources and sanitization are recorded in [release asset provenance](../docs/RELEASE-ASSET-PROVENANCE.md).

## Hosting

The public site is generated with `npm run build:pages` and published from the
root of the dedicated `gh-pages` branch. The branch contains only the reviewed
static output and `.nojekyll`; no repository or Cloudflare secret is used.
Publication is manual rather than coupled to every `master` push. See the
complete [GitHub Pages publication contract](../docs/GITHUB-PAGES-PUBLICATION.md).

GitHub handles Pages requests and states that it logs visitor IP addresses for
security. That provider processing is not project telemetry or analytics. See
GitHub's [Pages data-collection notice](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
and [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

`.openai/hosting.json` remains scoped to the owner-only preview project and
declares no D1 or R2 capability. Its Worker output disables request logs/traces
with `observability.enabled: false`; Cloudflare may still provide aggregate
platform request metrics for that preview. The public Pages branch deployment
does not use that configuration or deploy to the user's Cloudflare account.
Neither hosting path authorizes a GitHub Release or download link.
