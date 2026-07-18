# Public surface readiness audit

Date: 2026-07-18

## Outcome

The local user-facing open-source surface is prepared for the Desk Setup
Switcher `v0.1.0` public-beta candidate. It now explains one deliberate product
journey—**Capture → Edit → Review & Apply**—without adding product features or
turning an unsigned development artifact into a download.

This is not a public launch. No site, repository setting, tag, GitHub Release,
DMG, or promotional post was published or changed remotely. Developer ID
signing, notarization, Gatekeeper, protected release controls, external beta
installs, canonical URLs, and explicit maintainer publication approval remain
open gates.

## Prepared surface

- The root [README](../README.md) leads with user value, the three-step flow,
  sanitized screenshots, the absent-download boundary, a one-minute quick
  start, permissions, support limits, and contribution/security routes.
- The [English guide](guides/USER-GUIDE.md) and
  [Korean guide](guides/USER-GUIDE.ko.md) cover installation, Capture/Edit/Review
  & Apply, protected change and rollback, import/export, diagnostics,
  troubleshooting, update, uninstall, and local-data deletion.
- The [profile schema](PROFILE-SCHEMA.md) and
  [adapter contract](ADAPTER-CONTRACT.md) document interchange and contributor
  integration boundaries without presenting the internal Swift packages as a
  stable SDK or plug-in API.
- [Launch copy](LAUNCH-COPY.md) contains reviewed description/topics and
  English/Korean holding, release, and community copy. Placeholders and an
  approval checklist prevent pre-release text from being mistaken for an
  authorized post.
- `site/` is a bilingual single-page static route with no account, database,
  object storage, project-set cookies, project analytics, client-side tracking,
  telemetry, remote font, remotely loaded third-party runtime script, or app
  download.
  Application code persists no product or visitor data. The built vinext
  router's two technical, tab-scoped `sessionStorage` navigation/reload guards
  are pinned and disclosed. The release control remains disabled copy until
  the complete public-release gate passes.
- The built Worker has no D1, R2, Analytics Engine, or external-service binding
  and sets `observability.enabled: false`. Cloudflare's unavoidable aggregate
  request metrics are disclosed as hosting-provider operations, not represented
  as absent or as project product analytics.

## Media and provenance

The site uses three public derivatives from DEBUG-only synthetic UI fixtures:

1. Capture empty state;
2. Display profile editor; and
3. the current-tree Apply Preview representing Review & Apply, regenerated
   after the rollback wording was made explicitly best-effort.

The derivatives are opaque RGB PNGs with no embedded ICC profile. The 37-second
H.264 demo uses only those stills, has no audio stream, provides English and
Korean WebVTT captions, and stops at review instead of simulating a successful
Apply. The 1280×640 social preview combines a retained generated abstract
background with the exact project icon, exact sanitized editor capture, and
deterministic AppKit text. Full hashes, sources, transformations, licensing,
and the image-generation prompt are in
[release asset provenance](RELEASE-ASSET-PROVENANCE.md).

`make verify-public-assets` checks the eight-file public checksum manifest and
nine-file source/AX evidence manifest, exact PNG geometry/opacity/profile
boundary, high-confidence embedded sensitive strings, video
stream/codec/duration, caption structure/timeline, social-card size, and icon
byte identity.

## Verification

The local surface passed:

- repository-wide non-live `make verify`: 908 deterministic checks/assertions—
  501 app checks (178 XCTest, 322 default Swift Testing cases across 39 suites,
  and one isolated native popover case in a 40th Swift Testing suite) plus 407
  release-tooling assertions (328 Ruby policy and 79 shell guard assertions)—
  plus lint/localization policy, Swift and universal Xcode Debug/Release,
  Analyze, DMG/checksum, mounted resources/architectures, and
  ad-hoc/no-Developer-ID classification; the release assertions are simulated
  and do not prove a credentialed signing/notarization run;
- unsigned development-package verification at SHA-256
  `c1b406b4a29571ed721c0c0255c9d2220bdefb601a8c6639e0f136c41820c503`;
- `npm run verify` in `site/`: static build, lint, server-rendered HTML tests,
  no-cookie assertion, application-source tracking/storage scan, a built-client
  gate that allows only vinext's two named navigation/reload guards, disabled
  observability, no data/service binding, starter-capability absence, and
  required-media checks;
- `npm audit`: zero known vulnerabilities in the pinned site dependency graph;
- `make verify-public-assets`: all eight declared public assets plus nine
  source/AX evidence files and their SHA-256 entries verified;
- local HTTP checks for the page, social image metadata, OG/Twitter fields, and
  200 responses for the social image and silent MP4;
- visual inspection of the three public screenshots, four demo timestamps, and
  final social preview for synthetic-only data and correct orientation/copy;
- the complete-history/current-asset public-release audit on the integrated
  tree; and
- `git diff --check` on the integrated tree.

These are local, non-live development and public-surface checks. The DMG was not
installed or launched, and no public deployment, push, tag, release, or
promotional post was made.

## UX decision record

- The primary narrative stays at three steps and describes the native screen
  title **Apply Preview** as the Review & Apply stage.
- Capture is explicitly read-only; Apply remains a separate confirmation.
- The site exposes evidence levels next to Display, Audio, and Network instead
  of compressing mock verification into a hardware-support claim.
- Installation content appears, but the download control is intentionally
  unavailable and says why. There is no disabled button that looks actionable.
- Language switching is in-memory UI state only. It creates no cookie, product
  storage, local preference, or network consequence.
- Full assistive-technology certification is not marketed as a feature or
  release gate. Keyboard behavior, accessible names/values, and non-color state
  cues remain ordinary UI quality requirements.

## Evidence limits

A formal browser-driven Product Design screenshot audit was not run. The
repository prohibits UI automation and ordinary mouse/keyboard mutation, and
the in-app Browser surface was unavailable. The site was therefore reviewed
through static rendering/tests, local HTTP responses, source inspection, and
direct inspection of its public image/video frames. Responsive behavior,
interactive language switching, native video-caption selection, browser focus
order, contrast, and zoom/reflow still require a bounded manual browser pass
before publication.

No display, audio, network, Location/TCC, login-item, Keychain, mouse, or
keyboard mutation was performed. The media does not provide hardware evidence,
and the website does not change the app's support matrix.

The integrated source also removes runtime coordinate collection/cache and its
Settings refresh surface; Location authorization remains only for reading the
current Wi-Fi SSID during explicit Capture. Profile schema decoding, included
ColorSync validation, and snapshot capability-group handling now fail closed,
and protected-change copy describes rollback as a best-effort restore attempt.
These deterministic safeguards do not constitute live TCC or hardware evidence.

## Remaining launch path

1. Configure protected default-branch/release-environment controls and private
   vulnerability reporting without weakening the human publication gate.
2. Produce one canonical hardened Developer ID candidate, sign the DMG, obtain
   and staple notarization, verify app and DMG with Gatekeeper, and attach
   checksum, SBOM, attestation/provenance, and redownload identity evidence.
3. Complete clean-quarantine install/upgrade/uninstall and three external Apple
   Silicon beta reports with no unresolved P0/P1 issue.
4. Merge and publish the guides, support forms, and security policy to the
   default branch before deploying the site, then verify every public link from
   a clean session. Run the bounded manual site/browser and final bilingual copy
   review, set the approved HTTPS metadata origin and canonical release URL,
   then rerun every local and remote gate.
5. Ask the maintainer for explicit approval of the artifact, tag, release
   notes, site publication, repository metadata, social preview, and each
   promotional post before any public mutation.
