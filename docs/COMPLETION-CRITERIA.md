# Completion criteria and evidence ledger

This ledger separates current implementation/test/local-commit gates from historical package/CI evidence and optional or unapproved manual hardware/release work. Tray Surface v2 is the current production source. A user-provided installed screenshot exposed the pre-correction first-row gap and profile-draft refresh action; the corrected source is covered by non-live tests and detached-host evidence but has not yet completed the installed interaction checklist. All `MenuBarExtra` package/interaction evidence is historical and cannot be used to check v2 popover behavior. Hardware-dependent rows may have mock/read-back evidence while remaining explicitly “not hardware-verified.”

## Evidence snapshot — historical baselines and current follow-up

| Evidence | Result |
| --- | --- |
| Repository/product documentation milestone | Committed and pushed as `aaea058` |
| Implementation milestone | Commit `0d8f510` pushed to `origin/master` |
| CI repair milestone | Commit `4e45328` pushed to `origin/master` |
| UI-hardening implementation milestone | Commit `5f0cabc` pushed to `origin/master` |
| Toolchain | Xcode 26.6, Swift 6.3.3, macOS 26.5.2, Apple M5; process-local `DEVELOPER_DIR` fallback |
| Historical full local verification | Post-fix `make verify` passed on 2026-07-11: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Analyze, package, checksum, and mounted-DMG inspection |
| GitHub Actions | Run `29154880831` for `0d8f510` recorded the Swift 6.1 actor-isolation failure. [Run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) for repair `4e45328` succeeded on 2026-07-11 under macOS 15, Xcode 16.4, and Swift 6.1.2; full `make verify` and unsigned-package upload passed |
| Preceding UI implementation checks | Header/editor `make lint`, `make build`, and 215 default non-live tests passed: 112 XCTest with five skips plus 103 Swift Testing cases with one skip. The 56 presentation-specific tests comprised 29 draft XCTest and 27 presentation/condition Swift Testing cases |
| Preceding UI full local gate | Header/editor `make verify` passed with localization/policy lint, 215 tests, Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc signature classification. Historical local DMG SHA-256: `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b` |
| Preceding UI push/CI | UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); the later local header/editor follow-up was not pushed or run in CI |
| Apply-reliability full local gate | `make verify` passed on 2026-07-14: lint/localization policy; 290 default cases (124 XCTest with five skips plus 166 Swift Testing with one skip), zero failures; Swift Debug/Release; universal Xcode Debug/Release; Analyze; DMG/checksum; mounted resources/architectures; and ad-hoc signature classification. Separately, `git diff --check` passed |
| Apply-reliability synthetic UI review | Historical source/pure-test mapping covers Ready, Partial, unavailable/no-op, dirty decisions, capture, validation, result states, and disclosure. No rendered layout was recorded at that milestone |
| Apply-reliability commit/push/release | Behavior-focused commit `e242ec4` exists locally. Push, GitHub Actions, Developer ID signing, notarization, and release were not performed |
| Current Tray Surface v2 full local gate | `make verify` passed on 2026-07-15: lint/localization policy; 326 default cases (130 XCTest + 196 Swift Testing) with six opt-in skips, zero failures; Swift Debug/Release; universal Xcode Debug/Release; Analyze; DMG/checksum; mounted resources/architectures; and ad-hoc signature classification |
| Most recent synthetic UI evidence | [Tray Surface v2 audit](TRAY-SURFACE-AUDIT-2026-07-15.md) records 12 English/Korean detached-host PNGs and 12 read-only metadata files. Empty/1/3/10 profiles, overflow, deletion, permission, success/failure/result, dark, simulated large text, and one high-contrast appearance passed visual/size/privacy review. Detached accessibility children and actual popover chrome are explicitly unproven |
| Installed interaction evidence | No v2 installed interaction was performed. Historical user-authorized logs cover the superseded `MenuBarExtra` surface, Settings resize/state preservation, and store rollback only; they do not prove the new status-item/popover lifecycle |
| Current audit isolation | Deterministic `UIAuditSafetyTests` proves public audit actions do not invoke injected adapters, condition readers, profile storage, diagnostics, login-item service, UserDefaults, or Core Location requests |
| Default test behavior | Six cases skip without explicit opt-in: five read-only hardware cases and one Keychain-write round trip |
| Opt-in live reads | On 2026-07-14, display, audio, network, input, and combined readiness-context tests all passed on the current capture-permission source with `DESK_SETUP_LIVE_READ_TESTS=1`; the display gate covered an online-but-inactive sleeping session without inventing active displays, the live Keychain write remained skipped, and no setting mutation was run |
| Xcode/package architectures | Current Debug/Release builds and packaged executable verified as `x86_64 arm64`; x86_64 was not run on Intel hardware |
| Tray Surface v2 baseline package | Universal no-Developer-ID DMG with ad-hoc-signed app; SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`. It passed checksum, mount, metadata, resources, architectures, and signature classification and is now historical evidence |
| Current installed app | Not performed for Tray Surface v2. No UI automation, launch, store access, TCC action, or system setting mutation occurred during this task |
| Historical CI package | Downloaded artifact ID `8256718472` verified its checksum file; CI-generated DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. Local and CI DMGs are not byte-for-byte reproducible; no new CI run was requested |
| Install smoke | The current verified DMG completely replaced the existing `/Applications` bundle and its matching binary launched. The actual status item, deletion Esc/Cancel/Confirm, resizable Settings state preservation, Capture purpose explanation, and stable app System-window permission handoff passed scoped installed interactions |
| Snapshot profile | Created one schema-v1 Ready profile from a read-only snapshot with all four groups; the zero-operation plan kept Apply and Force Apply disabled |
| Login item | Default-on registration succeeded; BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history |
| Live mutations | Not run for display, audio, network, mouse, or keyboard |
| Live Keychain write | Not run |
| Optional/unapproved evidence gaps | Full VoiceOver/keyboard order, import/export/TCC permission matrix, real macOS text size, quarantined Gatekeeper install, physical Intel, login-item approval/retry and actual login-at-boot after a reboot, live Keychain write, live mutation/rollback, signing/notarization, release tag, and publication |

No test evidence contains a real SSID, exact location, IP host address, credential, serial number, or personal device identifier.

## Product and app lifecycle

- [x] Checked-in Xcode project, shared scheme, Swift Package targets, and deterministic project generator passed `make build` on the preceding header/editor tree.
- [x] The preceding Swift and universal Xcode Debug/Release builds passed through `make build`.
- [x] The preceding header/editor tree passed the full `make verify` Release/package gate as universal `arm64 x86_64`; physical Intel execution remains pending.
- [x] The integrated apply-reliability tree passed `make verify`, replacement package/checksum verification, and `git diff --check` on 2026-07-14.
- [x] The final-source stable permission-handoff tree passed 301-case `make verify` and replacement package/checksum verification. The separate opt-in five-case live-read smoke run passed on the immediately preceding capture source on 2026-07-14 without mutation.
- [x] Tray Surface v2 passed 326-case non-live `make verify`, deterministic lifecycle/action/geometry coverage, localization validation, detached-host evidence generation, universal package/checksum verification, and `git diff --check`.
- [x] Production uses one app-owned `NSStatusItem`, `.applicationDefined` `NSPopover`, and `NSHostingController`; `MenuBarExtra(.window)` and measured outer-height feedback are absent.
- [x] Every tray action has one typed disposition; stay-open, visible/key handoff, failure/cancel, duplicate click, stale generation, and quit-only termination cases pass.
- [ ] Actual v2 status-item/popover opening, anchor/arrow/material/ghost-frame behavior, native dismissal timing, and first responder are manually verified.
- [x] A fresh copy from the final locally built DMG launches from `/Applications`.
- [x] The fresh install launched background-only/menu-bar-only and exposed its popover without a normal app lifecycle.
- [x] Default-on `SMAppService` registration, status inspection, UI opt-out, and re-enable passed; final cleanup opted out and left only disabled BTM history.
- [ ] Approval-required and failure/retry login-item paths, plus actual login-at-boot after a reboot, are manually verified.
- [ ] English and Korean UI coverage is complete. Current catalogs and exact runtime-bundle tests pass; six English and six Korean current-source static states passed visual/AX review, but complete interactive and linguistic-quality review remains pending.
- [ ] VoiceOver, keyboard-only navigation, focus order, contrast, transparency, and macOS text-size behavior are audited. V2 source tests and simulated `.accessibility3`/high-contrast evidence pass, but the detached host exposes no virtual SwiftUI children and full assistive-technology/real-system-setting behavior remains pending.

## Profiles and storage

- [x] Core create, read, edit, duplicate, delete, reorder, select, and reload behavior passes temporary-store tests; corresponding SwiftUI actions are implemented.
- [x] A fresh installed app manually created one schema-v1 Ready profile from a read-only snapshot with all four setting groups.
- [x] Name, description, symbol, enabled state, conditions, group inclusion, and per-option inclusion are represented in versioned persisted models.
- [x] Schema 0→1 migration, current schema round trip, legacy whole-second dates, and future/missing migration rejection pass tests.
- [x] Atomic writes, last-known-good backup, primary/backup corruption quarantine, recovery, failed-update state preservation, 0700 directories, and 0600 managed files pass temporary-file tests.
- [x] Import/export enforces the 5 MiB limit, schema/semantic limits, unique IDs, valid selection, regular-file input, source protection, and exclusive no-overwrite output.
- [x] Last application summary is persisted back into the profile and contains typed item statuses/messages without credential fields. Manual relaunch/readback remains part of the app audit.
- [x] Unsupported display rotation/active state and administrative IPv4/DNS/proxy values are preserved but idempotently excluded at decode, store, import, capture, and planning boundaries; deterministic synthetic tests cover value retention and groups with no applicable leaves.

## UI hardening

- [x] A pure app-lifetime draft session distinguishes saved and editable profile values, detects user-field changes, and unit-tests save/discard/cancel selection resolution, failed or mismatched save completion, external refreshes, and authoritative metadata preservation.
- [x] Selection, creation, duplication, deletion, import, snapshot replacement, and ordinary termination use the shared dirty-draft decision path in source; fixed save/revert state and `⌘S` compile in the current app build.
- [x] Settings exposes only fixed Revert/Save draft actions; the ambiguous current-settings draft refresh action and helper copy are absent. Tray Capture remains read-only and creates a new reviewable profile through the existing typed snapshot boundary.
- [x] Tray capture returns a value-free complete/permission-needed/failure presentation, rejects captures with no applicable leaf, and never exposes an SSID. An explicit Capture action explains undetermined Location permission; denied/restricted states offer System Settings or Wi-Fi-free capture. The persistent permission workflow must become visible and key before router close; deterministic ordering is covered without live TCC mutation. Actual v2 TCC/focus interaction remains unchecked.
- [x] User-facing capture results retain saved applicable leaves and actionable permission gaps only. Snapshot-only, unreadable, unsupported, and runtime-identifier evidence is omitted from presentation; the always-unsupported network service-order query and item were removed.
- [x] Deterministic presentation logic summarizes included display/audio/network/input values, keeps opaque identifiers in technical details, preserves imported symbols, and models Ready/Partial/Unavailable/Applying, locked, disabled, and zero-operation actions.
- [x] Setting inclusion and disclosure are independent in source; collapsing preserves configured values. The dense editor `Form` is replaced by wider card groups and padded option rows beside regular-size Include controls, avoiding the observed Korean Audio-row compression. Common display/audio/network/input values use typed pickers, toggles, semantic sliders, and a typed ephemeral display-mode catalog, while unsupported snapshot-only values are read-only and never persisted as catalog metadata.
- [x] A pure field validator reports localized field identifiers for missing leaves/values, ranges, modes, addresses, masks, DNS, ports, and input bounds before save; the UI attaches non-color invalid/error metadata and first-error focus routing.
- [x] Tray/apply source uses one state-aware primary slot plus direct Edit and a named destructive Delete control. Delete confirmation stays inside the profile card and fixed open-session viewport; one scroll region owns overflow, while Cancel/`Esc` changes no storage. Ready + operations selects normal Apply and Partial + executable operations selects Apply Available. Ellipsis, separate availability review, and manual refresh remain absent.
- [x] The tray top-scroll request is generation-tagged and emitted only after popover attachment; its anchor is the first content block rather than a spacing-producing sibling. Focused tests cover stale attachment and 20 reopen generations.
- [x] Settings/workflow windows participate in the ordinary macOS app/window cycle while any destination is visible, remain app-lifetime persistent across app switching, and restore tray-only accessory policy after the last explicit close or failed presentation. Two-window policy and ten-cycle controller reuse are deterministic-test covered.
- [x] Apply resolves a same- or other-profile dirty draft through save/discard/cancel before planning, never silently uses an older saved value, and then preserves the existing fresh profile/snapshot stale-plan comparison.
- [x] Condition editing is absent while existing/imported conditions remain round-trip compatible but dormant and non-blocking for current manual readiness, preview, and execution. Earlier evaluator/choice/input-validation tests remain compatibility coverage.
- [x] Compact and detailed apply results expose succeeded/failed/skipped/unsupported/rollback/not-verified outcomes without raw values. Fresh read-only replanning marks a still-required succeeded operation not verified; intentional force omissions remain separate.
- [x] Profiles/System/About is the primary Settings information architecture. System distinguishes desired and actual login state, keeps only relevant permission guidance visible, and presents diagnostics as an on-demand advanced troubleshooting sheet. About exposes source/issues/license/privacy links, and diagnostics pair severity symbols with text.
- [x] English/Korean localization lint passes for key parity, duplicate keys, format placeholders, and statically discoverable UI keys; exact runtime-bundle tests assert unknown-key, action, role, experimental-input, and numeric formatting in both languages.
- [x] Accessibility source includes labeled icon actions, distinct inclusion/target values, field invalid/error metadata, non-color state text, save/apply/result announcements, display-confirmation shortcuts, and a remaining-time value. Current AX logs confirm profile rows expose one combined name/state element rather than duplicates. Full assistive-technology behavior remains manually unverified.
- [x] Sixteen English/Korean standard editor, overview, validation, System, advanced diagnostics, 680×480 minimum, simulated large-text, and current deletion/capture/save-feedback states passed static visual/AX review with synthetic data. Actual deletion Esc/Cancel/Confirm, Settings open/reopen, 980→680→980 selection/draft/disclosure/focus preservation, and Capture-to-System handoff passed scoped installed interactions.
- [ ] Exact denied/granted permission-result-card actions, complete keyboard-only traversal, VoiceOver speech/focus, contrast, transparency, and real macOS text-size behavior are manually verified. These remain pending.

## Snapshot and adapters

- [x] Snapshot distinguishes detected/storable, unreadable, permission-required, and unsupported values, and isolates one group's read failure from the others.
- [x] Display adapter has stable matching, snapshot, validation, atomic plan, complete rollback payload, app-only initial apply, and session-only confirmation/rollback. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Audio adapter uses Core Audio UIDs and covers input/output/system defaults, scalar output volume/mute, no-op filtering, and unsupported controls. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Network adapter covers discovery, permission/ambiguity-aware SSID, Wi-Fi power, and saved-network association without profile passwords. Target and rollback saved-access preflight is required before switching. Mock/live-read verified; mutation not hardware-verified.
- [x] Input adapter covers common pointer/scroll/repeat/delay/F-key settings and labels the undocumented preference-key mechanism experimental. Mock verified and live-read verified; mutation not hardware-verified.
- [x] Display rotation/activation and administrative network mutations are omitted with typed reasons rather than private APIs or unsafe authorization shortcuts.
- [x] Input preference writes perform an immediate injected snapshot/read-back and return failure when the freshly read value disagrees. This is deterministic mock/read-back verification, not evidence of perceived hardware behavior.
- [x] Source contains no vendor configuration, UI automation, third-party file mutation, automatic switching, telemetry, or arbitrary shell execution path.

## Conditions and apply engine

- [x] All/any and per-item/set inversion pass for display, audio input/output, USB/hardware, SSID, Ethernet, IPv4/IPv6 CIDR, and authorized-location conditions.
- [x] Permission/source failure isolation, conservative display matching, hashed USB identity, location accuracy/age behavior, and unknown/unavailable inversion semantics pass tests.
- [x] Ready, Partial, and Unavailable for the current manual path derive from normalized item capabilities and are shown with text and symbols, not color alone; legacy conditions are deliberately not a hidden gate.
- [x] Normal apply rejects disabled, incomplete, unavailable, or fatally invalid profiles; dormant legacy conditions do not reject a manual plan.
- [x] Force apply records omissions and rejects a zero-operation plan.
- [x] The fresh snapshot profile presented a zero-operation plan with both Apply and Force Apply disabled; no live setting mutation occurred.
- [x] Immediately before execution, the app recaptures conditions/snapshots and refreshes the plan; changed profile, operations, omissions, or rollback payloads return to preview instead of executing stale state.
- [x] After execution, or after a high-risk display Keep decision, the app runs fresh read-only preparation and separates verified, not-verified, intentional omission, and newly remaining operations. Historical applied/failed status no longer permanently masks refreshed readiness.
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
- [x] The preceding default unit and mock integration suites passed locally with 215 tests: 112 XCTest and 103 Swift Testing cases; six explicit opt-in cases skipped and no live setting change was part of the run.
- [x] The preceding header/editor tree's `make lint` and `make build` passed.
- [x] The preceding header/editor tree's `make analyze`, full `make verify`, package/checksum, and mounted-image verification passed. Its verified local DMG SHA-256 is `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`.
- [x] The apply-reliability follow-up's new deterministic Core/Presentation/System regressions and all existing default tests passed in one integrated `make verify` run: 124 XCTest with five skips plus 166 Swift Testing cases with one skip, zero failures.
- [x] The apply-reliability follow-up produced and verified its replacement universal package/checksum: SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`.
- [x] The UI-audit follow-up's deterministic localization and system-access isolation regressions plus all existing default tests passed in one integrated `make verify` run: 129 XCTest plus 168 Swift Testing cases, six opt-in skips, zero failures.
- [x] Tray Surface v2 produced and verified its baseline universal package/checksum: SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`. The measured-height SHA-256 `8bf4d547fae0df3cbe999db84e7be169b33d495b3993cf7c37f46ba37d6ea71d` and pre-correction SHA-256 `8422b042b793bf0845ac56e2dcbd9808075a0467226d79ee65408440736648d8` remain historical.
- [x] GitHub Actions passes on pushed UI-hardening commit `5f0cabc`: [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) completed full `make verify` and unsigned-package upload.
- [x] Versioned no-Developer-ID DMG contains the ad-hoc-signed universal app and `/Applications` link.
- [x] SHA-256 validation and mounted-DMG metadata/resource/architecture/signature checks pass locally; the Tray Surface v2 baseline checksum is `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`. Earlier measured-height, permission-handoff, installed-interaction, capture, tray/editor, layout, apply-reliability, and post-fix checksums remain historical in the roadmap/support matrix.
- [x] Downloaded historical CI artifact ID `8256718472` verifies against its checksum file; its DMG SHA-256 is `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. It is distinct from the local DMG because packaging is not byte-for-byte reproducible. Historical artifact `8249295840` remains recorded in the support matrix.
- [ ] Manual release review is complete. Historical fresh `/Applications` launch, background/menu-bar-only behavior, snapshot-profile creation, and login-item transitions passed; current static bilingual/AX evidence plus actual deletion, resize state/focus, Settings open/reopen, and stable permission handoff also passed. Gatekeeper, login approval/retry/reboot, import/export, the full permission matrix, full accessibility, and mutation paths remain.
- [x] Signing status is accurately classified: ad-hoc integrity signature only, no Developer ID identity, no notarization, and no claim of Gatekeeper trust.
- [x] Mandatory implementation, test, package, push, and CI gates are complete for the historical repair commit `4e45328`.
- [x] Mandatory full verification, package, push, and CI gates are complete for UI-hardening commit `5f0cabc`.
- [ ] The header/editor follow-up has matching push and CI artifact evidence. It is locally verified but has not been pushed in this task.
- [x] The apply-reliability follow-up has a verified behavior-focused local commit and a clean worktree. This row is closed by the final commit/status handoff; push/CI evidence is not required by its current goal and must not be inferred.
- [x] The UI-audit follow-up has a verified behavior-focused local commit and a clean worktree. This row is closed by the final commit/status handoff; push/CI evidence is not required and must not be inferred.
- [ ] Optional release publication and manual/hardware evidence are complete. They remain unapproved or unrun and do not negate the completed implementation gates.

## Tray/settings refinement completion ledger

- [x] The final non-live `make verify` passes localization/source policy, 339 cases (132 XCTest + 207 Swift Testing, six opt-in skips), Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted metadata/resources/`x86_64 arm64`, and ad-hoc signature classification.
- [x] The verified local no-Developer-ID DMG SHA-256 is `567917f169e90799db177d0a5f22a8b13115cb30ed63f7e766fc4bb992ab35e3`; it was not installed, launched, pushed, or published.
- [x] Twenty deterministic reopen cycles retain fixed content size and zero AppKit host origins; every attached generation receives one fresh top-scroll request, stale attachment is ignored, and the anchor adds no layout row.
- [x] Settings and Profile Edit each survive ten red-close/reopen cycles through the same app-lifetime controller/root, destination visible/key/front completion precedes tray dismissal, and a shared activation coordinator retains ordinary window behavior until the final destination is hidden.
- [x] Quit uses localized `xmark` semantics and the status item derives applying/matching/fallback state without trusting stale last-application data.
- [x] Alias, icon, and enabled state share one adaptive row; description, conditions, Input, and hidden legacy settings remain round-trip compatible while normalized out of new apply payloads.
- [x] Display, Audio, and Network expose only the requested controls; color mode and service IPv4 communicate their unsupported mutation boundary rather than reporting success.
- [x] Core Audio input volume implements snapshot, validation, planning, application, rollback, diagnostics, unsupported/non-settable, and missing-device paths with synthetic tests.
- [x] Network service IPv4 uses portable Ethernet/Wi-Fi identity, validates DHCP/manual data, handles ambiguity nonfatally, and never persists a runtime service ID as sole identity.
- [x] English/Korean keys, accessibility/help text, non-color reasons, 12 refreshed 0/1/3/10/long-Korean tray pairs, and five standard/minimum/large-text/dark profile-editor PNG/AX pairs are recorded in [TRAY-SETTINGS-REFINEMENT-AUDIT-2026-07-15.md](TRAY-SETTINGS-REFINEMENT-AUDIT-2026-07-15.md).
- [ ] Actual installed status-item/popover geometry, red-close/frontmost behavior, native bilingual rendering, keyboard traversal, and VoiceOver are manually verified.
- [ ] Display/audio/network hardware mutation and rollback are verified. These remain explicitly unrun and are not required for the non-live implementation gate.
- [ ] Push, CI, tag, signing/notarization, or release publication is performed for this milestone. They remain operator decisions outside the local goal.

## Manual hardware evidence format

Use the shared and group-specific procedures in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md). Record date, macOS version, app commit, redacted hardware class, exact procedure, expected result, actual result, rollback result, sanitized diagnostic event IDs, and tester. A mock test, successful read-only snapshot, cross-architecture build, or successful apply without restore is not hardware-mutation evidence.
