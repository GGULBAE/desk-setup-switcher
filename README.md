# Desk Setup Switcher

> **Open-source public-beta candidate, not yet released:** the local baseline is security-hardened and fully verified, but the current DMG is development-only. A supported download still requires Developer ID signing, notarization, stapling, Gatekeeper and clean-install evidence, protected release approval, and external beta results.

Desk Setup Switcher is a free and open-source macOS menu-bar app for manually saving and applying display, audio, and network profiles. Older mouse, keyboard, condition, and legacy setting data remains round-trip compatible but dormant. The app is local-first: no account, server, cloud sync, telemetry, analytics, or automatic profile switching.

## What is implemented

- A native `LSUIElement` app whose tray is owned by `NSStatusItem` + `NSPopover` + `NSHostingController`, with persistent Settings/workflow windows, profile capture, editing, ordering, import/export, readiness, normal/force previews, itemized results, and a 15-second protected display/network confirmation flow.
- App-lifetime profile drafts with save/discard/cancel protection across selection, replacement, and ordinary quit paths. `⌘S` saves a valid dirty draft, and fixed save/revert controls remain outside the editor scroll area. Current settings are captured from the tray as a new reviewable profile rather than silently replacing an open editor draft.
- A pristine empty tray exposes one labelled **Capture Current Settings** primary action in the body, with help that states it reads without changing the Mac. Nonempty and non-idle states retain one compact header Capture action, so Capture is never duplicated. Empty idle content is centered outside scrolling; empty and first-profile states share a 260-point viewport, two profiles use 316 points, and overflow is capped at 560. Each profile keeps one state-aware primary action, direct Edit, and inline destructive confirmation.
- Every tray open creates a new top-anchored scroll identity. AppKit retains the attached popover wrapper's nonzero origin around its arrow/chrome; the app maps only the hosted SwiftUI child to the wrapper's local bounds. The public container also preserves vertical native safe area while filtering horizontal exclusion before SwiftUI layout. Cached readiness stays visible during refresh, duplicate status presentations are ignored, and status-item title/width changes are deferred until the popover closes so its menu-bar anchor cannot move underneath it.
- Settings uses an app-owned resizable macOS window with a 680×480 content minimum. The profile workspace keeps one horizontal anatomy across the entire supported range: a fixed 210-point sidebar, divider, and scrolling editor with fixed footer/action bars. **New Profile** is the one direct management action; Duplicate/Delete, Move Up/Down, and Import/**Export Saved Profiles…** are grouped in one secondary menu. A dirty draft visibly states that Export uses saved profiles only. Each presentation keeps its runtime capability catalog stable during a read-only refresh, adopts the completed snapshot once, and resets profile scroll only when the profile changes or a hidden Settings window is reopened.
- Profile metadata exposes alias and icon only. Legacy `isEnabled == false` decodes and migrates to active applicability; it no longer hides a profile or blocks apply. Display, Audio, and Network groups are flat and always expanded. Each leaf now says **Apply with profile**, shows Included/Not included text plus a non-color symbol, and exposes setting-specific accessibility value/help.
- The default editor exposes Display output mode, primary display, per-display resolution/refresh, and portable ColorSync ICC profile; Audio default input/output and settable input/output volumes; and exact Ethernet/Wi‑Fi service DHCP/manual IPv4. Description, conditions, Input, display origin/rotation/active state, system-output/mute, Wi‑Fi power/SSID, global IPv4, DNS, and proxies still round-trip but are dormant and excluded from new apply payloads.
- Apply never silently uses an older saved profile when an editor draft is dirty. The save/discard/cancel decision identifies the draft and target profile, and preparation is repeated against the latest stored profile and read-only system state before execution. The preview says that no setting has changed yet; a changed execution preflight returns a visible refreshed review without mutation, and every rejected confirmation displays a reason instead of silently returning. JSON operation payloads are compared canonically, so harmless object-key ordering cannot cause an infinite refreshed-review loop while changed values and rollback evidence still stop execution.
- Capture checks Location authorization before reading a Wi-Fi name. An undetermined state gets a privacy explanation followed by the macOS request; a denied/restricted state offers macOS System Settings or an explicit Wi-Fi-free capture. Permission, dirty-draft, preview, safety-confirmation, and result-detail work is app-lifetime state presented in persistent windows. Presentation has a bounded liveness deadline and independently cancellable duplicate callers; red-close detaches an in-flight request before cancellation so an immediate reopen cannot inherit stale state. Failure or cancellation leaves the tray reachable with an error.
- Workflow decision, preview, protected confirmation, result, and error surfaces keep long content scrollable above stable safe actions at the 520×360 minimum or under accessibility text. Long profile-specific meaning remains in accessibility labels, operation/result rows switch from grids to vertical layout when needed, and each transition selects a heading plus an enabled safe Cancel/Revert/Close keyboard target. About and Advanced Diagnostics also reflow inside the 680×480 Settings contract.
- Display rotation/active state and administrative IPv4, DNS, and proxy values are retained as snapshot-only values but normalized out of application for new, stored, and imported profiles. Legacy/imported conditions remain round-trip compatible but are dormant and non-blocking for current manual readiness and apply; condition editing and automatic switching are absent.
- A single `VisibleSettingRegistry` declares the nine visible setting kinds and the required capture/edit/validate/plan/apply/verify/rollback stages. Typed runtime catalogs project only controls that can complete that contract; Audio volume capability follows the profile-selected device. Unsupported, read-only, missing, or ambiguous rows stay absent for new choices. If a previously included Audio, ColorSync, or service-IPv4 value later becomes unavailable, the editor keeps a warning and an Include-off repair control while planning records an explicit omission instead of a false success. Field-specific validation blocks invalid saves and exposes non-color/accessibility error metadata.
- Value-first profile summaries and apply previews keep technical identifiers behind app-owned disclosures with explicit localized Expanded/Collapsed values and next-action hints, preserve imported symbols through a curated icon picker, explain disabled actions with text, and retain accessible keyboard/value metadata. After execution, an itemized result distinguishes succeeded, failed, skipped, unsupported, rollback, and not-verified outcomes; a fresh read-only plan prevents a still-needed operation from being labelled applied. The installed disclosure Return/Space and AX result is control-scoped; VoiceOver was not run and no VoiceOver claim is made.
- Versioned profile JSON, semantic/resource validation, safe actionable validation errors, migration scaffolding, permission-restricted Application Support persistence with private staging before atomic replacement, last-known-good backup, corruption quarantine, and exclusive-create export. Store and import reads reject traversal, symbolic links, non-regular files, wrong owners, oversized input, and detected source replacement; sensitive rewrites and quarantine compare descriptor-bound file identity. Generic storage failures use a prominent heading/icon/card with one real Retry Loading or Dismiss Error recovery action, temporarily disable the profile workspace, and clear stale editor feedback; editor-owned save failures remain a single editor error instead of duplicating the global card.
- A capability-driven adapter contract and transaction engine with deterministic ordering, no-op filtering, pre-execution state/rollback revalidation, one active transaction, reverse rollback after fatal failure, and protected high-risk rollback tokens.
- Read-only display, audio, network, input, USB/hardware, and authorized-location discovery using macOS frameworks.
- Concrete display, audio, and network apply adapters, plus a dormant experimental input compatibility adapter. Display topology uses public Core Graphics; ColorSync profile targets persist a registered ID plus ICC-file SHA-256 and resolve runtime URLs only from the current public catalog. Core Audio switches devices before device-scoped volume. Service-specific IPv4 uses authorized public SystemConfiguration writes, exact serialized rollback data, commit/apply/unlock checks, dynamic-store completion, and exact read-back. Display and network changes remain protected until Keep/Revert resolves. These mutation paths are deterministic mock verified only; ordinary tests and CI never change host settings.
- Local diagnostic redaction and rotating JSONL storage with sanitized snapshot/apply/storage/login/safety events and on-demand advanced browsing, refresh, and confirmed clearing from the System tab. Diagnostics are troubleshooting tools rather than a primary navigation destination. Diagnostic export is not implemented.
- A deterministic checked-in Xcode project generator, Swift Package targets, build/test/lint/analyze/package scripts, and GitHub Actions definitions.

The authoritative scope is [docs/PRODUCT.md](docs/PRODUCT.md). Architecture and safety boundaries are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/TECHNICAL-SPEC.md](docs/TECHNICAL-SPEC.md). The current release-preparation record is the [open-source release baseline audit](docs/OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md). The [P2 UI refinement audit](docs/P2-UI-REFINEMENT-AUDIT-2026-07-17.md) and its preceding installed/structural audits remain historical UI evidence.

## Verification status

Evidence is intentionally split by confidence level:

| Evidence | Current result |
| --- | --- |
| Current open-source release baseline | [Open-source release baseline audit](docs/OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md) records storage/import hardening, explicit launch-at-login consent, public-history and image-metadata auditing, frozen release identities, honest support/distribution boundaries, accepted P2 filesystem limits, and remaining publication gates |
| Current full local gate | Final integrated result: 496 checks (173 XCTest + 322 Swift Testing across 40 suites + one isolated native popover regression). Lint, Debug/Release builds, universal Xcode builds, Analyze, project generation, checksum, mounted resources/architectures, and ad-hoc signature inspection passed |
| Current development package | Universal ad-hoc/no-Developer-ID DMG SHA-256: `961f4044996c0f5fc0b4e8e782355da4d620c553e4c1891918d19323f6d67eac`. It was not installed or launched and is not a public, supported, signed, notarized, stapled, or Gatekeeper-verified release |
| Historical P2 UI refinement audit | [P2 UI refinement audit](docs/P2-UI-REFINEMENT-AUDIT-2026-07-17.md) records the completed empty-tray CTA, profile-action hierarchy, saved-only dirty Export contract, explicit inclusion and disclosure semantics, minimum-size auxiliary fixtures, Settings-tab routing, prominent storage recovery, final synthetic review, and bounded installed keyboard/AX result |
| Preceding UI/UX installed audit | [UI/UX simplification and installed-app audit](docs/UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md) records the attached-wrapper root cause, wrapper-ownership fix, persistent-window sizing and async-generation hardening, preceding package gate, installed geometry, safety invariants, and the P2 ledger that this pass implements |
| Preceding structural regression gate | The [native UI structural reliability audit](docs/UI-STRUCTURAL-RELIABILITY-AUDIT-2026-07-17.md) records the preceding selective-safe-area, destination-window, responsive-workflow, and synthetic-evidence work. Its focused run passed 52 tests across five suites; the final attached-native wrapper regression is recorded by the current audit |
| Preceding settings-lifecycle refactor | [Settings lifecycle and UI declutter audit](docs/SETTINGS-LIFECYCLE-REFACTOR-2026-07-16.md) records the editor→store→fresh reload→apply→read-back proof, unavailable-target repair policy, storage-failure guarantees, and remaining filesystem boundary work |
| Historical P2 full local gate | Final integrated result: 461 checks (144 XCTest + 316 Swift Testing across 39 suites + one isolated native popover regression). Do not infer this result from the preceding 446-check gate |
| Preceding full local gate | The structural-fix integrated gate passed on 2026-07-17 with 446 checks: 144 XCTest cases, 301 Swift Testing cases across 38 suites, and one separately executed native `NSPopover` regression. Localization/policy lint, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum creation, mounted metadata/resources/`x86_64 arm64`, and ad-hoc/no-Developer-ID classification all passed |
| Preceding UI-stability audit | [Tray, Settings, and workflow UI stability audit](docs/UI-STABILITY-AUDIT-2026-07-16.md) records the three installed references, root-cause analysis, before/after tray and full Settings-root renders, default and minimum-large-text apply previews, accessibility review, deterministic regressions, and remaining installed/manual limits |
| Preceding UI-stability full local gate | `make verify` passed on 2026-07-16 with localization/policy lint, 375 default cases (134 XCTest, including five skips, + 241 Swift Testing, including two disabled opt-in cases), Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification |
| Historical P2 UI evidence | The [P2 evidence index](docs/evidence/p2-ui-refinement-2026-07-17/README.md) records 39 fixtures and 79 generated and inspected artifacts (15 tray, 13 Settings, three apply-preview, two responsive-workflow, six auxiliary, plus one Settings footer comparison note). The final DMG was reinstalled; `⌘,` routes Profiles from visible System/About and close→reopen/stale cases. Installed disclosure Return expands and Space collapses while AX value/hint/child presence update. VoiceOver was not run, was explicitly removed from P2 completion scope on 2026-07-18, was restored disabled, and is not claimed |
| Historical P2 package and install | Universal no-Developer-ID DMG SHA-256: `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`; reinstalled `/Applications` executable SHA-256: `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719`. The preceding structural package hashes remain historical and must not be reused |
| Preceding end-to-end UI evidence | The [installed evidence index](docs/evidence/ui-ux-installed-2026-07-17/README.md) records the structural-fix installed screenshots, 20-open geometry, package hashes, and unchanged safety-state hashes. The [tray and Settings end-to-end audit](docs/TRAY-SETTINGS-END-TO-END-AUDIT-2026-07-16.md) retains the broader preceding synthetic matrix |
| Preceding structural-fix package and install | The structural package verified `x86_64 arm64`, English/Korean resources, `/Applications` link, mounted layout, and ad-hoc/no-Developer-ID status at DMG SHA-256 `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`; its reinstalled executable SHA-256 was `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305` |
| Tray Surface v2 baseline | `make verify` passed on 2026-07-15 with lint/localization policy, 326 default cases (130 XCTest + 196 Swift Testing, six opt-in skips), Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification. No live flag was set |
| Tray Surface v2 baseline UI evidence | [Tray Surface v2 audit](docs/TRAY-SURFACE-AUDIT-2026-07-15.md) records 12 English/Korean detached-host PNGs and 12 read-only metadata files covering empty/1/3/10 profiles, deletion, permission, success/failure, result, dark, large-text, and high-contrast fixtures. That baseline proves contained SwiftUI layout only; the current installed centering follow-up is recorded above |
| Tray Surface v2 baseline package | The preceding universal package verified `x86_64 arm64`, English/Korean resources, mounted layout, and ad-hoc/no-Developer-ID signature status at SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`; it is retained as historical evidence rather than the current artifact |
| Installed app follow-up | User-provided 2026-07-16 and 2026-07-17 screenshots exposed an asymmetric empty state, ambiguous Apply-to-review wording, and then a repeated refreshed-review loop. The current package was reinstalled to `/Applications`; 20 measured popover opens had exact center delta `0`, Settings clamped `500×300` to `680×480` and retained `900×568` across ten normal opens, and workflow clamped `500×300` to `520×392`, opened at frame `620×532` with `620×500` content, and closed with Escape. Apply, Capture, TCC, login, and system-setting mutations were not invoked |
| Historical pre-layout-fix UI-audit package | The preceding UI-audit DMG passed the same local gate with SHA-256 `fa42df665ca453165dd041fe5112a8f1a6d2314bd31512ef9371b12289132122`; its installed Korean Settings rendering exposed the Audio-row compression corrected in the current package |
| Historical apply-reliability package | The preceding 290-case apply-reliability DMG passed the same local build/mount gate with SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`; it predates the UI-audit follow-up |
| Previous header/editor full gate | `make verify` passed on 2026-07-12: localization/policy lint, 215 tests (112 XCTest + 103 Swift Testing), Swift and universal Xcode Debug/Release, Analyze, DMG creation, checksum, mounted-image resources, architectures, and ad-hoc signature classification. The 56 presentation-specific tests comprise 29 draft and 27 presentation/condition cases |
| Previous local universal package | The header/editor no-Developer-ID DMG verified `arm64 x86_64`, bundle metadata, icon, English/Korean resources, `/Applications` link, ad-hoc app signature, and SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`; it predates this follow-up |
| Historical full local gate | Repair baseline `4e45328` passed `make verify` on 2026-07-11: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Xcode Analyze, packaging, checksum, and mounted-DMG checks |
| Default test behavior | Five XCTest cases skip by default: four read-only hardware/context cases and one Keychain-write round trip. Two Swift Testing cases—dormant input read and adjacent live apply preparation—are disabled without explicit read-only opt-in. No live setting mutation or Keychain write runs in the default suite |
| Current live read-only discovery | On 2026-07-14, all five opt-in display, audio, network, input, and readiness-context smoke tests passed on the immediately preceding capture-permission source on an Apple M5 Mac running macOS 26.5.2. The display path also passed while the online session display was asleep and Core Graphics correctly reported zero active displays. The stable handoff changes affect only app-layer presentation. The live Keychain write remained skipped, and no setting mutation was run |
| Current adjacent-plan live read | On 2026-07-16, the selected profile was prepared twice in both normal and available-items modes after canonicalization. Both adjacent plans were execution-equivalent in 0.148 seconds. The test was read-only, reported only sanitized equality flags, and invoked no adapter mutation |
| Historical local universal package | The 2026-07-11 post-fix no-Developer-ID DMG verified `arm64 x86_64`, bundle metadata, icon, English/Korean resources, `/Applications` link, ad-hoc app signature, and SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f` |
| Historical CI universal package | [Actions run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) uploaded unsigned artifact ID `8249295840`; its downloaded checksum file verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. Local and CI DMGs are not byte-for-byte reproducible |
| Historical manual packaged app | The 2026-07-11 local-DMG copy launched from `/Applications` as background-only/menu-bar-only; the Korean popover, Settings, and one accessibility label passed inspection. This does not verify the current UI tree |
| Historical snapshot profile | That fresh install created one schema-v1 **Ready** profile from a read-only snapshot with all four setting groups; because it was a zero-operation plan, both Apply and Force Apply were disabled |
| Historical login item | Default-on `SMAppService` registration succeeded and Background Task Management reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out, leaving only disabled BTM history |
| Live mutations | **Not run** for display, audio, network, mouse, or keyboard |
| Live Keychain write | **Not run**; the Keychain path is mock verified |
| Remaining manual checks | Popover arrow/material/ghost-frame and outside-click/deactivation behavior, complete full-app keyboard order and focused-control AX state, real contrast/text-size/transparency settings, TCC denial/grant, Gatekeeper/quarantine, physical Intel, login approval/retry/reboot, import/export interaction, and mutation/rollback procedures remain pending and nonblocking for historical P2. Full-app VoiceOver certification is excluded and is not tracked as release completion work |
| Historical CI universal package | UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967): full `make verify` and unsigned artifact ID `8256718472` upload succeeded. The downloaded checksum file verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`; current push/CI status is reported in the implementation handoff. No release is published |

See the [support matrix](docs/SUPPORT-MATRIX.md) and [completion ledger](docs/COMPLETION-CRITERIA.md) for capability-level evidence and explicit manual procedures.

## Platform and limits

- macOS 14 Sonoma or later
- Native Swift/SwiftUI
- Universal `arm64` and `x86_64` build target; no physical Intel Mac has been tested
- Menu-bar-only accessory app with an `SMAppService` login-item preference that defaults off and changes only after explicit user opt-in
- Public macOS APIs for display, audio, and network operations
- Experimental labels for common input preferences backed by undocumented global preference keys
- Display rotation/activation, display origin editing, HDR/pixel-encoding modes, Wi‑Fi power/association, global IPv4, DNS/proxy/service-order mutation, input preferences, vendor configuration, UI scripting, and automatic switching are absent from the default surface. Legacy values remain readable and round-trip compatible but dormant. Portable ColorSync ICC mapping and exact per-service IPv4 are the supported color/network mutations in the current mock-verified contract
- No-Developer-ID DMG baseline: the app has a free ad-hoc integrity signature, but no trusted publisher identity and no notarization
- MIT licensed

## Development

Use full Xcode with a Swift 6.1-or-later toolchain. The local reference environment is Xcode 26.6 with Swift 6.3.3. Scripts select `/Applications/Xcode.app` through a process-local `DEVELOPER_DIR` fallback when `xcode-select` points to Command Line Tools; they do not change global developer-directory state.

```sh
make build
make test
make lint
make analyze
make audit-public-release
make package
make verify-package
make verify
make clean
```

`make verify` is the primary gate: lint, tests, Debug/Release Swift and universal Xcode builds, Xcode Analyze, no-Developer-ID DMG creation, checksum validation, ad-hoc signature inspection, and mounted-DMG verification. It must not perform live discovery or a setting mutation. `make audit-public-release` separately requires complete Git history and checks historical text and image metadata for high-confidence credential and personal-path patterns without printing matched secret values.

`make lint` also validates English/Korean key parity, duplicate keys, format-placeholder compatibility, and statically discoverable localized UI keys. Passing this structural check is not a rendered bilingual walkthrough or a linguistic-quality audit.

The following gate opts into the repository's read-only hardware discovery tests. It still does not apply settings:

```sh
DESK_SETUP_LIVE_READ_TESTS=1 make test
```

Live mutation tests are not part of the ordinary suite or CI. Do not add or run one without an explicit environment gate, an interactive user action, a preflight snapshot, and a documented rollback path.

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## Privacy and security

Profiles, backups, and diagnostics are local. Exported profiles can contain user-selected device/network labels, network ranges, SSIDs, and exact latitude/longitude plus radius for location conditions; review or remove those values before sharing. They never contain Wi-Fi passwords. Saved-network association relies on credentials already managed by macOS; Keychain support is isolated and tested with synthetic data.

Read [docs/PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Packaging and distribution

`make package` creates `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` and its `.sha256` file with a universal app and `/Applications` link. The “unsigned” filename means no Developer ID identity: the contained app is ad-hoc signed for code integrity and to meet the packaging design's signature prerequisite, but is not notarized. `make verify-package` checks the checksum, mounts the image read-only, and validates metadata, resources, both architectures, and signature class.

The current development-only DMG SHA-256 is `961f4044996c0f5fc0b4e8e782355da4d620c553e4c1891918d19323f6d67eac`. It was not installed or launched. Nothing is published: Developer ID signing with hardened runtime and secure timestamp, notarization, stapling, Gatekeeper verification, SBOM/provenance, clean-quarantine testing, protected approval, and external beta evidence are mandatory before the public beta. Full-app VoiceOver certification is deliberately outside that release gate and is not claimed. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Historical P2 UI refinement

The bounded P2 source implements the empty-tray primary Capture CTA; one direct New Profile action plus a grouped secondary menu; explicit saved-only dirty Export semantics; unambiguous Apply-with-profile state; explicit disclosure value/hint semantics; a Diagnostics minimum contained by Settings; minimum-size Korean accessibility-text fixtures for About, safety, result, error, and diagnostics; stale-safe `⌘,` Profiles routing; and prominent single-action storage recovery. The 461-check gate, 39-fixture/79-artifact review, final package/install hashes, routing checks, and installed disclosure Return/Space with AX updates are recorded in the [audit](docs/P2-UI-REFINEMENT-AUDIT-2026-07-17.md). VoiceOver was not run, full-app VoiceOver certification was removed from completion scope, and no such claim is made. Complete keyboard traversal and focused-control AX observation remain separate nonblocking manual evidence. No Apply Profile, Capture, TCC, login, or hardware-setting mutation was invoked.

## Project tracking

- [Historical UI refinement goal](docs/UI-REFINEMENT-GOAL.md)
- [Locally verified apply reliability and editor UX follow-up](docs/APPLY-RELIABILITY-UX-GOAL.md)
- [Current-source manual UI audit](docs/MANUAL-UI-AUDIT-2026-07-14.md)
- [Tray Surface v2 audit](docs/TRAY-SURFACE-AUDIT-2026-07-15.md)
- [Tray and Settings refinement audit](docs/TRAY-SETTINGS-REFINEMENT-AUDIT-2026-07-15.md)
- [Tray/settings end-to-end audit](docs/TRAY-SETTINGS-END-TO-END-AUDIT-2026-07-16.md)
- [Installed empty/apply follow-up](docs/INSTALLED-EMPTY-APPLY-FOLLOWUP-2026-07-16.md)
- [Tray, Settings, and workflow UI stability audit](docs/UI-STABILITY-AUDIT-2026-07-16.md)
- [UI/UX simplification and installed-app audit](docs/UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md)
- [Native UI structural reliability audit](docs/UI-STRUCTURAL-RELIABILITY-AUDIT-2026-07-17.md)
- [P2 UI refinement audit](docs/P2-UI-REFINEMENT-AUDIT-2026-07-17.md)
- [P2 UI refinement evidence](docs/evidence/p2-ui-refinement-2026-07-17/README.md)
- [Open-source release baseline audit](docs/OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md)
- [Compatibility and versioning](docs/COMPATIBILITY.md)
- [Distribution](docs/DISTRIBUTION.md)
- [Roadmap](docs/ROADMAP.md)
- [Completion criteria](docs/COMPLETION-CRITERIA.md)
- [Support matrix](docs/SUPPORT-MATRIX.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE) © 2026 GGULBAE.
