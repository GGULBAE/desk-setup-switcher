# Completion criteria and evidence ledger

This ledger prevents implementation from being reported as release completion. A checked row requires source/tests in the milestone commit and the named local evidence. Hardware-dependent rows may have mock evidence while remaining explicitly “not hardware-verified.” Final release gates stay unchecked until the integrated commit, clean verification, push, CI, and manual procedures are complete.

## Evidence snapshot — 2026-07-11

| Evidence | Result |
| --- | --- |
| Repository/product documentation milestone | Committed and pushed as `aaea058` |
| Implementation milestone | Commit `0d8f510` pushed to `origin/master` |
| Toolchain | Xcode 26.6, Swift 6.3.3, macOS 26.5.2, Apple M5; process-local `DEVELOPER_DIR` fallback |
| Full local verification | Post-fix full `make verify` passed: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Analyze, package, checksum, and mounted-DMG inspection |
| GitHub Actions | Run `29154880831` for `0d8f510` failed in `make verify` under Xcode 16.4/Swift 6.1.2: `NetworkSystemAPI` used a `??` autoclosure over actor-isolated `[String: Any]`. The local repair extracts Sendable values first; repaired commit/push and a green retry are pending |
| Default test behavior | Six cases skip without explicit opt-in: five read-only hardware cases and one Keychain-write round trip |
| Opt-in live reads | Display, audio, network, input, and combined readiness-context tests passed with `DESK_SETUP_LIVE_READ_TESTS=1` |
| Xcode/package architectures | Current Debug/Release builds and packaged executable verified as `arm64 x86_64`; x86_64 was not run on Intel hardware |
| Final package | Post-fix universal `arm64 x86_64` no-Developer-ID DMG with ad-hoc-signed app; SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f` |
| Fresh-install smoke | Copied from the final DMG to `/Applications` and launched background-only/menu-bar-only; Korean popover/Settings and an accessibility label passed |
| Snapshot profile | Created one schema-v1 Ready profile from a read-only snapshot with all four groups; the zero-operation plan kept Apply and Force Apply disabled |
| Login item | Default-on registration succeeded; BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history |
| Live mutations | Not run for display, audio, network, mouse, or keyboard |
| Live Keychain write | Not run |
| Still pending | Repaired commit/push and green Actions retry, full VoiceOver/keyboard/import/export/permission matrix, quarantined Gatekeeper install, physical Intel, login-item approval/retry and actual login-at-boot after a reboot, live Keychain write, and live mutation/rollback |

No test evidence contains a real SSID, exact location, IP host address, credential, serial number, or personal device identifier.

## Product and app lifecycle

- [x] Checked-in Xcode project, shared scheme, Swift Package targets, and deterministic project generator pass the local verification gate.
- [x] Current-tree Swift and Xcode Debug builds pass with warnings as errors through `make verify`.
- [x] Current-tree Release app and DMG executable verify as universal `arm64 x86_64`; physical Intel execution is pending.
- [x] A fresh copy from the final locally built DMG launches from `/Applications`.
- [x] The fresh install launched background-only/menu-bar-only and exposed its popover without a normal app lifecycle.
- [x] Default-on `SMAppService` registration, status inspection, UI opt-out, and re-enable passed; final cleanup opted out and left only disabled BTM history.
- [ ] Approval-required and failure/retry login-item paths, plus actual login-at-boot after a reboot, are manually verified.
- [ ] English and Korean UI coverage is complete. The fresh-install popover/settings rendered in Korean, but a complete bilingual walkthrough remains pending.
- [ ] VoiceOver, keyboard-only navigation, focus order, contrast, and macOS text-size behavior are audited. One accessibility label passed inspection, but the full manual audit is pending.

## Profiles and storage

- [x] Core create, read, edit, duplicate, delete, reorder, select, and reload behavior passes temporary-store tests; corresponding SwiftUI actions are implemented.
- [x] A fresh installed app manually created one schema-v1 Ready profile from a read-only snapshot with all four setting groups.
- [x] Name, description, symbol, enabled state, conditions, group inclusion, and per-option inclusion are represented in versioned persisted models.
- [x] Schema 0→1 migration, current schema round trip, legacy whole-second dates, and future/missing migration rejection pass tests.
- [x] Atomic writes, last-known-good backup, primary/backup corruption quarantine, recovery, failed-update state preservation, 0700 directories, and 0600 managed files pass temporary-file tests.
- [x] Import/export enforces the 5 MiB limit, schema/semantic limits, unique IDs, valid selection, regular-file input, source protection, and exclusive no-overwrite output.
- [x] Last application summary is persisted back into the profile and contains typed item statuses/messages without credential fields. Manual relaunch/readback remains part of the app audit.

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
- [x] `make lint` source audit passes and rejects shell, outbound-networking, and UI-scripting primitives after all implementation changes.

## Quality, packaging, and delivery

- [x] Required repository, community, privacy, architecture, support, asset-provenance, and distribution documentation exists.
- [x] Current default unit and mock integration suites pass locally; live setting changes are not part of them.
- [x] `make lint` and `make analyze` pass on the integrated tree.
- [x] Post-fix local `make verify` passes with the generated Xcode project, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, and package verification.
- [ ] GitHub Actions passes on the repaired pushed tree. Run `29154880831` for milestone `0d8f510` failed under Xcode 16.4/Swift 6.1.2; the compatible local repair passes but is not yet pushed or green in Actions.
- [x] Versioned no-Developer-ID DMG contains the ad-hoc-signed universal app and `/Applications` link.
- [x] SHA-256 validation and mounted-DMG metadata/resource/architecture/signature checks pass locally; the post-fix checksum is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`.
- [ ] Manual release review is complete. Fresh `/Applications` launch, background/menu-bar-only behavior, Korean rendering, popover, Settings, one accessibility label, snapshot-profile creation, and basic login-item state transitions passed; Gatekeeper, login approval/retry/reboot, import/export, permissions, full accessibility, and mutation paths remain.
- [x] Signing status is accurately classified: ad-hoc integrity signature only, no Developer ID identity, no notarization, and no claim of Gatekeeper trust.
- [ ] Working tree is clean after the final release-candidate commit and all completed milestones are pushed.
- [ ] No mandatory release item remains; hardware-unverified capabilities remain explicitly labelled and have approved manual procedures.

## Manual hardware evidence format

Use the shared and group-specific procedures in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md). Record date, macOS version, app commit, redacted hardware class, exact procedure, expected result, actual result, rollback result, sanitized diagnostic event IDs, and tester. A mock test, successful read-only snapshot, cross-architecture build, or successful apply without restore is not hardware-mutation evidence.
