# Completion criteria and evidence ledger

This ledger separates mandatory implementation/test/package/push/CI gates from optional or unapproved manual hardware evidence and release publication. The 2026-07-11 repair baseline retains its committed full-gate evidence. UI-hardening commit `5f0cabc` has matching local and GitHub Actions full-gate evidence; the later menu-simplification follow-up has a full local gate but no new push/CI evidence. Hardware-dependent rows may have mock evidence while remaining explicitly “not hardware-verified.”

## Evidence snapshot — 2026-07-11 baseline and 2026-07-12 UI tree

| Evidence | Result |
| --- | --- |
| Repository/product documentation milestone | Committed and pushed as `aaea058` |
| Implementation milestone | Commit `0d8f510` pushed to `origin/master` |
| CI repair milestone | Commit `4e45328` pushed to `origin/master` |
| UI-hardening implementation milestone | Commit `5f0cabc` pushed to `origin/master` |
| Toolchain | Xcode 26.6, Swift 6.3.3, macOS 26.5.2, Apple M5; process-local `DEVELOPER_DIR` fallback |
| Historical full local verification | Post-fix `make verify` passed on 2026-07-11: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Analyze, package, checksum, and mounted-DMG inspection |
| GitHub Actions | Run `29154880831` for `0d8f510` recorded the Swift 6.1 actor-isolation failure. [Run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) for repair `4e45328` succeeded on 2026-07-11 under macOS 15, Xcode 16.4, and Swift 6.1.2; full `make verify` and unsigned-package upload passed |
| Current UI implementation checks | `make lint`, `make build`, and 214 default non-live tests pass: 111 XCTest with five skips plus 103 Swift Testing cases with one skip. The 55 presentation-specific tests comprise 28 draft XCTest and 27 presentation/condition Swift Testing cases |
| Current UI full local gate | Menu-simplification follow-up `make verify` passed with localization/policy lint, 214 tests, Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc signature classification. Local DMG SHA-256: `a6c539267b1103537d041c6181ee822356db69c91ecf8e6467ccd8c7154d6473` |
| Current UI push/CI | UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); the local menu-simplification follow-up has not been pushed or run in CI |
| Default test behavior | Six cases skip without explicit opt-in: five read-only hardware cases and one Keychain-write round trip |
| Opt-in live reads | Display, audio, network, input, and combined readiness-context tests passed with `DESK_SETUP_LIVE_READ_TESTS=1` |
| Xcode/package architectures | Current Debug/Release builds and packaged executable verified as `arm64 x86_64`; x86_64 was not run on Intel hardware |
| Current local package | Menu-follow-up universal `arm64 x86_64` no-Developer-ID DMG with ad-hoc-signed app; SHA-256 `a6c539267b1103537d041c6181ee822356db69c91ecf8e6467ccd8c7154d6473` |
| Current CI package | Downloaded artifact ID `8256718472` verified its checksum file; CI-generated DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. Local and CI DMGs are not byte-for-byte reproducible |
| Historical fresh-install smoke | A recorded 2026-07-11 local-DMG copy to `/Applications` launched background-only/menu-bar-only; Korean popover/Settings and an accessibility label passed. This is not a current-tree walkthrough |
| Snapshot profile | Created one schema-v1 Ready profile from a read-only snapshot with all four groups; the zero-operation plan kept Apply and Force Apply disabled |
| Login item | Default-on registration succeeded; BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history |
| Live mutations | Not run for display, audio, network, mouse, or keyboard |
| Live Keychain write | Not run |
| Optional/unapproved evidence gaps | Current-tree screenshot/layout walkthrough, full VoiceOver/keyboard/import/export/TCC permission matrix, quarantined Gatekeeper install, physical Intel, login-item approval/retry and actual login-at-boot after a reboot, live Keychain write, live mutation/rollback, release tag, and publication |

No test evidence contains a real SSID, exact location, IP host address, credential, serial number, or personal device identifier.

## Product and app lifecycle

- [x] Checked-in Xcode project, shared scheme, Swift Package targets, and deterministic project generator pass `make build` on the current UI tree.
- [x] Current-tree Swift and universal Xcode Debug/Release builds pass through `make build`.
- [x] Current UI tree passes the full `make verify` Release/package gate as universal `arm64 x86_64`; physical Intel execution remains pending.
- [x] A fresh copy from the final locally built DMG launches from `/Applications`.
- [x] The fresh install launched background-only/menu-bar-only and exposed its popover without a normal app lifecycle.
- [x] Default-on `SMAppService` registration, status inspection, UI opt-out, and re-enable passed; final cleanup opted out and left only disabled BTM history.
- [ ] Approval-required and failure/retry login-item paths, plus actual login-at-boot after a reboot, are manually verified.
- [ ] English and Korean UI coverage is complete. Current catalogs pass structural parity/duplicate/placeholder/static-key checks, and the baseline fresh-install popover/settings rendered in Korean, but a complete current-tree bilingual walkthrough remains pending.
- [ ] VoiceOver, keyboard-only navigation, focus order, contrast, and macOS text-size behavior are audited. Current source/build includes labels, announcements, display default/Escape shortcuts, and remaining-time accessibility values; one baseline label passed inspection, but the full current-tree manual audit is pending.

## Profiles and storage

- [x] Core create, read, edit, duplicate, delete, reorder, select, and reload behavior passes temporary-store tests; corresponding SwiftUI actions are implemented.
- [x] A fresh installed app manually created one schema-v1 Ready profile from a read-only snapshot with all four setting groups.
- [x] Name, description, symbol, enabled state, conditions, group inclusion, and per-option inclusion are represented in versioned persisted models.
- [x] Schema 0→1 migration, current schema round trip, legacy whole-second dates, and future/missing migration rejection pass tests.
- [x] Atomic writes, last-known-good backup, primary/backup corruption quarantine, recovery, failed-update state preservation, 0700 directories, and 0600 managed files pass temporary-file tests.
- [x] Import/export enforces the 5 MiB limit, schema/semantic limits, unique IDs, valid selection, regular-file input, source protection, and exclusive no-overwrite output.
- [x] Last application summary is persisted back into the profile and contains typed item statuses/messages without credential fields. Manual relaunch/readback remains part of the app audit.

## UI hardening

- [x] A pure app-lifetime draft session distinguishes saved and editable profile values, detects user-field changes, and unit-tests save/discard/cancel selection resolution, failed or mismatched save completion, external refreshes, and authoritative metadata preservation.
- [x] Selection, creation, duplication, deletion, import, snapshot replacement, and ordinary termination use the shared dirty-draft decision path in source; fixed save/revert state and `⌘S` compile in the current app build.
- [x] Current-settings capture remains read-only, returns a typed result, and replaces only draft settings until an explicit successful save.
- [x] Deterministic presentation logic summarizes included display/audio/network/input values, keeps opaque identifiers in technical details, preserves imported symbols, and models Ready/Partial/Unavailable/Applying, locked, disabled, and zero-operation actions.
- [x] Menu/apply source uses one primary Apply action, direct profile editing into the Profiles tab, secondary available-items apply, automatic menu-open readiness refresh without manual review/refresh controls, text-and-symbol disabled reasons, bounded profile scrolling, an all-disabled state, adaptive previews, and progressive technical disclosure without changing transaction semantics.
- [x] Condition presentation tests cover stable detected choices, disconnected saved values, blank filtering, typed IP/CIDR validation, and finite bounded location validation; the built UI uses Picker-first entry and Advanced raw identifiers.
- [x] Permission/About/diagnostic source distinguishes desired and actual login state, limits mismatch guidance, exposes source/issues/license/privacy links, and pairs diagnostic severity symbols with text.
- [x] English/Korean localization lint passes for key parity, duplicate keys, format placeholders, and statically discoverable UI keys. This is not a rendered bilingual or linguistic-quality audit.
- [x] Accessibility source/build includes labeled icon actions, non-color state text, save/apply announcements, display-confirmation default/Escape shortcuts, and a remaining-time value. Full assistive-technology behavior remains manually unverified.
- [ ] Current-tree visual layout, long-content behavior, keyboard-only flow, VoiceOver speech/focus, contrast, transparency, and text-size behavior are manually verified with synthetic data.

## Snapshot and adapters

- [x] Snapshot distinguishes detected/storable, unreadable, permission-required, and unsupported values, and isolates one group's read failure from the others.
- [x] Display adapter has stable matching, snapshot, validation, atomic plan, complete rollback payload, app-only initial apply, and session-only confirmation/rollback. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Audio adapter uses Core Audio UIDs and covers input/output/system defaults, scalar output volume/mute, no-op filtering, and unsupported controls. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Network adapter covers discovery, permission/ambiguity-aware SSID, Wi-Fi power, and saved-network association without profile passwords. Target and rollback saved-access preflight is required before switching. Mock/live-read verified; mutation not hardware-verified.
- [x] Input adapter covers common pointer/scroll/repeat/delay/F-key settings and labels the undocumented preference-key mechanism experimental. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Display rotation/activation and administrative network mutations are omitted with typed reasons rather than private APIs or unsafe authorization shortcuts.
- [x] Source contains no vendor configuration, UI automation, third-party file mutation, automatic switching, telemetry, or arbitrary shell execution path.

## Conditions and apply engine

- [x] All/any and per-item/set inversion pass for display, audio input/output, USB/hardware, SSID, Ethernet, IPv4/IPv6 CIDR, and authorized-location conditions.
- [x] Permission/source failure isolation, conservative display matching, hashed USB identity, location accuracy/age behavior, and unknown/unavailable inversion semantics pass tests.
- [x] Ready, Partial, and Unavailable derive from item capabilities/conditions and are shown with text and symbols, not color alone.
- [x] Normal apply rejects disabled, incomplete, condition-failing, unavailable, or fatally invalid profiles.
- [x] Force apply records omissions and rejects a zero-operation plan.
- [x] The fresh snapshot profile presented a zero-operation plan with both Apply and Force Apply disabled; no live setting mutation occurred.
- [x] Immediately before execution, the app recaptures conditions/snapshots and refreshes the plan; changed profile, operations, omissions, or rollback payloads return to preview instead of executing stale state.
- [x] Operations are no-op filtered and deterministically ordered across input, audio, network, display, and risk.
- [x] A fatal failure rolls completed operations back in reverse order; nonfatal failure can continue.
- [x] Rollback failure remains distinguishable from the initiating error.
- [x] High-risk completion creates a bounded one-shot token. Display apply is temporary/app-only; confirmation promotes it to session scope, while failure, timeout/revert, and confirmation failure use reverse rollback. Real display mutation/restore is pending.

## Security, privacy, and diagnostics

- [x] Profiles/backups and diagnostics default to `~/Library/Application Support/Desk Setup Switcher/`; import/export uses only user-selected paths.
- [x] Profiles, operations, backups, exports, and diagnostics have no Wi-Fi password field. Saved association uses macOS-held credentials.
- [x] The `SecretStore` abstraction's Keychain implementation uses a fixed namespace, device-only after-first-unlock accessibility, update/add race handling, zeroed temporary write buffers, and secret-free errors. Mock verified; live write pending.
- [x] Semantic validation rejects blank/malformed/nonfinite/out-of-range profile, setting, and condition values; its actionable `LocalizedError` descriptions do not echo rejected values.
- [x] Redaction tests cover credentials, exact coordinates, SSIDs, IP host portions, home paths, and entry fields before persistence.
- [x] Rotating diagnostic JSONL storage enforces local directory/file permissions, size/count bounds, serialized complete entries, pruning, and scoped clearing; Settings browsing/refresh/clear is implemented.
- [ ] Permission explanations and denial isolation are manually verified for location/SSID. Source paths are nonfatal, but the user-facing matrix is pending.
- [x] Import validation prevents path-driven traversal/network access, rejects non-regular files and oversize input before decode, and never overwrites the source or an existing export.
- [x] Current-tree `make lint` passes source policy and English/Korean structural localization checks, rejecting shell, outbound-networking, and UI-scripting primitives.

## Quality, packaging, and delivery

- [x] Required repository, community, privacy, architecture, support, asset-provenance, and distribution documentation exists.
- [x] Current default unit and mock integration suites pass locally with 214 tests: 111 XCTest and 103 Swift Testing cases; six explicit opt-in cases skip and no live setting change is part of the run.
- [x] Current-tree `make lint` and `make build` pass.
- [x] Current-tree `make analyze`, full `make verify`, replacement package/checksum, and mounted-image verification pass. The verified local DMG SHA-256 is `a6c539267b1103537d041c6181ee822356db69c91ecf8e6467ccd8c7154d6473`.
- [x] GitHub Actions passes on pushed UI-hardening commit `5f0cabc`: [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) completed full `make verify` and unsigned-package upload.
- [x] Versioned no-Developer-ID DMG contains the ad-hoc-signed universal app and `/Applications` link.
- [x] SHA-256 validation and mounted-DMG metadata/resource/architecture/signature checks pass locally; the current UI-tree checksum is `a6c539267b1103537d041c6181ee822356db69c91ecf8e6467ccd8c7154d6473` and the historical post-fix checksum is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`.
- [x] Downloaded current CI artifact ID `8256718472` verifies against its checksum file; its DMG SHA-256 is `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. It is distinct from the local DMG because packaging is not byte-for-byte reproducible. Historical artifact `8249295840` remains recorded in the support matrix.
- [ ] Manual release review is complete. Fresh `/Applications` launch, background/menu-bar-only behavior, Korean rendering, popover, Settings, one accessibility label, snapshot-profile creation, and basic login-item state transitions passed; Gatekeeper, login approval/retry/reboot, import/export, permissions, full accessibility, and mutation paths remain.
- [x] Signing status is accurately classified: ad-hoc integrity signature only, no Developer ID identity, no notarization, and no claim of Gatekeeper trust.
- [x] Mandatory implementation, test, package, push, and CI gates are complete for the historical repair commit `4e45328`.
- [x] Mandatory full verification, package, push, and CI gates are complete for UI-hardening commit `5f0cabc`.
- [ ] The menu-simplification follow-up has matching push and CI artifact evidence. It is locally verified but has not been pushed in this task.
- [ ] Optional release publication and manual/hardware evidence are complete. They remain unapproved or unrun and do not negate the completed implementation gates.

## Manual hardware evidence format

Use the shared and group-specific procedures in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md). Record date, macOS version, app commit, redacted hardware class, exact procedure, expected result, actual result, rollback result, sanitized diagnostic event IDs, and tester. A mock test, successful read-only snapshot, cross-architecture build, or successful apply without restore is not hardware-mutation evidence.
