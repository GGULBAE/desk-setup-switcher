# Desk Setup Switcher

> **Pre-release 0.1.0 implementation candidate:** The tray follows one deterministic first-attach contract, ignores native asymmetric horizontal safe-area insets, and uses fixed 0/1/2/overflow height tiers. Its profile action is explicitly labelled Review because mutation begins only from the reviewed workflow's Apply Profile confirmation. Settings exposes only complete Display, Audio, and Network vertical slices: every rendered control has typed capture, edit, validation, plan, apply, read-back, and rollback support.

Desk Setup Switcher is a free and open-source macOS menu-bar app for manually saving and applying display, audio, and network profiles. Older mouse, keyboard, condition, and legacy setting data remains round-trip compatible but dormant. The app is local-first: no account, server, cloud sync, telemetry, analytics, or automatic profile switching.

## What is implemented

- A native `LSUIElement` app whose tray is owned by `NSStatusItem` + `NSPopover` + `NSHostingController`, with persistent Settings/workflow windows, profile capture, editing, ordering, import/export, readiness, normal/force previews, itemized results, and a 15-second protected display/network confirmation flow.
- App-lifetime profile drafts with save/discard/cancel protection across selection, replacement, and ordinary quit paths. `⌘S` saves a valid dirty draft, and fixed save/revert controls remain outside the editor scroll area. Current settings are captured from the tray as a new reviewable profile rather than silently replacing an open editor draft.
- The popover header provides compact Capture plus icon-only, accessibility-labelled Settings and Quit actions. Geometry is chosen once per open session for empty, single-profile, compact, or capped-overflow content and does not resize when banners, deletion confirmation, async results, or text size change. Each profile keeps one state-aware primary action, direct Edit, and inline destructive confirmation; overflow uses the single internal scroll view. `Review…` and `Review Available…` hand off to persistent workflows before the tray closes.
- Every tray open restores a zero-origin hosting viewport, shows the popover, then requests the single internal scroll view's top anchor. The anchor is attached directly to the first content block, so it contributes no layout spacing. Settings, Profile Edit, permission, preview, confirmation, and result destinations survive red-close through app-owned controllers; while any destination is visible the app uses the ordinary macOS activation/window cycle, and after the last destination is explicitly hidden it returns to tray-only accessory mode. The tray closes only after the destination is visible and key.
- Settings uses an app-owned resizable macOS window with a 680×480 content minimum. It remains open when another application or Space becomes active and closes only from an explicit window action. The profile workspace switches at 760 points without replacing the editor identity, preserving the selected profile, unsaved draft, and keyboard focus while resizing.
- Profile metadata exposes alias and icon only. Legacy `isEnabled == false` decodes and migrates to active applicability; it no longer hides a profile or blocks apply. Display, Audio, and Network groups are flat and always expanded, and each leaf has its own Include switch.
- The default editor exposes Display output mode, primary display, per-display resolution/refresh, and portable ColorSync ICC profile; Audio default input/output and settable input/output volumes; and exact Ethernet/Wi‑Fi service DHCP/manual IPv4. Description, conditions, Input, display origin/rotation/active state, system-output/mute, Wi‑Fi power/SSID, global IPv4, DNS, and proxies still round-trip but are dormant and excluded from new apply payloads.
- Apply never silently uses an older saved profile when an editor draft is dirty. The save/discard/cancel decision identifies the draft and target profile, and preparation is repeated against the latest stored profile and read-only system state before execution. The preview says that no setting has changed yet; a changed execution preflight returns a visible refreshed review without mutation, and every rejected confirmation displays a reason instead of silently returning. JSON operation payloads are compared canonically, so harmless object-key ordering cannot cause an infinite refreshed-review loop while changed values and rollback evidence still stop execution.
- Capture checks Location authorization before reading a Wi-Fi name. An undetermined state gets a privacy explanation followed by the macOS request; a denied/restricted state offers macOS System Settings or an explicit Wi-Fi-free capture. Permission, dirty-draft, preview, safety-confirmation, and result-detail work is app-lifetime state presented in persistent windows. The tray router waits for the destination to become visible and key before closing; failure or cancellation leaves the tray reachable with an error. User-facing results retain applicable settings and actionable permission gaps only.
- Display rotation/active state and administrative IPv4, DNS, and proxy values are retained as snapshot-only values but normalized out of application for new, stored, and imported profiles. Legacy/imported conditions remain round-trip compatible but are dormant and non-blocking for current manual readiness and apply; condition editing and automatic switching are absent.
- A single `VisibleSettingRegistry` declares the nine visible setting kinds and the required capture/edit/validate/plan/apply/verify/rollback stages. Typed runtime catalogs project only controls that can complete that contract; unsupported, read-only, missing, or ambiguous rows are omitted. Field-specific validation blocks invalid saves and exposes non-color/accessibility error metadata.
- Value-first profile summaries and apply previews keep technical identifiers behind disclosures, preserve imported symbols through a curated icon picker, explain disabled actions with text, and retain accessible keyboard/value metadata. After execution, an itemized result distinguishes succeeded, failed, skipped, unsupported, rollback, and not-verified outcomes; a fresh read-only plan prevents a still-needed operation from being labelled applied.
- Versioned profile JSON, semantic/resource validation, safe actionable validation errors, migration scaffolding, permission-restricted Application Support persistence, last-known-good backup, corruption quarantine, and exclusive-create export.
- A capability-driven adapter contract and transaction engine with deterministic ordering, no-op filtering, pre-execution state/rollback revalidation, one active transaction, reverse rollback after fatal failure, and protected high-risk rollback tokens.
- Read-only display, audio, network, input, USB/hardware, and authorized-location discovery using macOS frameworks.
- Concrete display, audio, and network apply adapters, plus a dormant experimental input compatibility adapter. Display topology uses public Core Graphics; ColorSync profile targets persist a registered ID plus ICC-file SHA-256 and resolve runtime URLs only from the current public catalog. Core Audio switches devices before device-scoped volume. Service-specific IPv4 uses authorized public SystemConfiguration writes, exact serialized rollback data, commit/apply/unlock checks, dynamic-store completion, and exact read-back. Display and network changes remain protected until Keep/Revert resolves. These mutation paths are deterministic mock verified only; ordinary tests and CI never change host settings.
- Local diagnostic redaction and rotating JSONL storage with sanitized snapshot/apply/storage/login/safety events and on-demand advanced browsing, refresh, and confirmed clearing from the System tab. Diagnostics are troubleshooting tools rather than a primary navigation destination. Diagnostic export is not implemented.
- A deterministic checked-in Xcode project generator, Swift Package targets, build/test/lint/analyze/package scripts, and GitHub Actions definitions.

The authoritative scope is [docs/PRODUCT.md](docs/PRODUCT.md). Architecture and safety boundaries are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/TECHNICAL-SPEC.md](docs/TECHNICAL-SPEC.md).

## Verification status

Evidence is intentionally split by confidence level:

| Evidence | Current result |
| --- | --- |
| Current installed-layout/apply follow-up | `make verify` passed on 2026-07-16 with localization/policy lint, 371 default cases (134 XCTest, including five skips, + 237 Swift Testing, including two disabled opt-in cases), Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification. Focused coverage injects an asymmetric native safe area, proves a stable reviewed plan reaches its adapter exactly once, preserves stale-value/rollback rejection, and treats reordered JSON object keys as the same plan |
| Current end-to-end UI evidence | [Tray and Settings end-to-end audit](docs/TRAY-SETTINGS-END-TO-END-AUDIT-2026-07-16.md) records the main synthetic matrix. The [installed empty/apply follow-up](docs/INSTALLED-EMPTY-APPLY-FOLLOWUP-2026-07-16.md) records the user-reported native symptoms, injected-safe-area regression, review/apply handoff tests, and evidence limits. Detached rendering does not prove installed status-item/window interaction, keyboard traversal, VoiceOver, or hardware behavior |
| Current end-to-end local package | `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` verified `x86_64 arm64`, English/Korean resources, `/Applications` link, mounted layout, and ad-hoc/no-Developer-ID status. SHA-256: `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`. It was reinstalled to `/Applications`; bundle identity, version, architectures, and signature passed read-only checks. It was not launched after replacement |
| Current Tray Surface v2 follow-up | `make verify` passed on 2026-07-15 with lint/localization policy, 326 default cases (130 XCTest + 196 Swift Testing, six opt-in skips), Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification. No live flag was set |
| UI evidence | [Tray Surface v2 audit](docs/TRAY-SURFACE-AUDIT-2026-07-15.md) records 12 English/Korean detached-host PNGs and 12 read-only metadata files covering empty/1/3/10 profiles, deletion, permission, success/failure, result, dark, large-text, and high-contrast fixtures. It proves contained SwiftUI layout only; actual status-item click behavior, popover arrow/material/ghost-frame behavior, first-responder timing, VoiceOver, and TCC remain manual |
| Tray Surface v2 baseline package | The preceding universal package verified `x86_64 arm64`, English/Korean resources, mounted layout, and ad-hoc/no-Developer-ID signature status at SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`; it is retained as historical evidence rather than the current artifact |
| Current installed app | User-provided 2026-07-16 screenshots exposed an asymmetric empty state, ambiguous Apply-to-review wording, and then a repeated refreshed-review loop. The loop was reproduced read-only as semantically identical audio JSON with different key order; the canonicalized follow-up package above replaced `/Applications/Desk Setup Switcher.app`. Native retry and actual user-confirmed setting mutation remain manual |
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
| Remaining manual checks | Actual v2 status-item opening, popover anchor/arrow/material/ghost-frame behavior, native outside-click/deactivation/Esc timing, first responder, complete keyboard order, VoiceOver, real contrast/text-size/transparency settings, TCC denial/grant, Gatekeeper/quarantine, physical Intel, login approval/retry/reboot, import/export, and mutation/rollback procedures are pending |
| Historical CI universal package | UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967): full `make verify` and unsigned artifact ID `8256718472` upload succeeded. The downloaded checksum file verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`; current push/CI status is reported in the implementation handoff. No release is published |

See the [support matrix](docs/SUPPORT-MATRIX.md) and [completion ledger](docs/COMPLETION-CRITERIA.md) for capability-level evidence and explicit manual procedures.

## Platform and limits

- macOS 14 Sonoma or later
- Native Swift/SwiftUI
- Universal `arm64` and `x86_64` build target; no physical Intel Mac has been tested
- Menu-bar-only accessory app with an `SMAppService` login-item preference
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
make package
make verify-package
make verify
make clean
```

`make verify` is the primary gate: lint, tests, Debug/Release Swift and universal Xcode builds, Xcode Analyze, no-Developer-ID DMG creation, checksum validation, ad-hoc signature inspection, and mounted-DMG verification. It must not perform live discovery or a setting mutation.

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

The current follow-up DMG passed build, checksum, mount, resource, architecture, and signature verification and was reinstalled to `/Applications` without launching it. Installation integrity does not prove the corrected native popover or hardware mutation path. Nothing is published; quarantine/Gatekeeper, approval-required and retry states, and actual login-at-boot after a reboot remain untested. Developer ID signing and notarization are optional external release-operator work, not current project claims. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Next task

The next task is a user-driven smoke check of the reinstalled build: launch it, open the empty tray repeatedly, and confirm the profile row now says Review before the separate Apply Profile confirmation. Any real Display, Audio, ColorSync, Ethernet, or Wi‑Fi mutation and rollback remains a separately controlled hardware-verification procedure.

## Project tracking

- [Historical UI refinement goal](docs/UI-REFINEMENT-GOAL.md)
- [Locally verified apply reliability and editor UX follow-up](docs/APPLY-RELIABILITY-UX-GOAL.md)
- [Current-source manual UI audit](docs/MANUAL-UI-AUDIT-2026-07-14.md)
- [Tray Surface v2 audit](docs/TRAY-SURFACE-AUDIT-2026-07-15.md)
- [Tray and Settings refinement audit](docs/TRAY-SETTINGS-REFINEMENT-AUDIT-2026-07-15.md)
- [Tray/settings end-to-end audit](docs/TRAY-SETTINGS-END-TO-END-AUDIT-2026-07-16.md)
- [Installed empty/apply follow-up](docs/INSTALLED-EMPTY-APPLY-FOLLOWUP-2026-07-16.md)
- [Roadmap](docs/ROADMAP.md)
- [Completion criteria](docs/COMPLETION-CRITERIA.md)
- [Support matrix](docs/SUPPORT-MATRIX.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE) © 2026 GGULBAE.
