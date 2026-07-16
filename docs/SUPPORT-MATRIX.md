# Support matrix

## Legend

- **Implemented:** source path exists, but no verification level is implied.
- **Unit verified:** deterministic pure logic passed without constructing live system adapters.
- **Mock verified:** deterministic injected/unit coverage passed; the real host was not changed.
- **Live-read verified:** an opt-in read-only test passed on the named hardware.
- **Hardware-mutation verified:** an explicit interactive apply and rollback procedure passed on physical hardware.
- **Experimental:** implementation uses a public preferences API with an undocumented key or lacks a stable supported OS contract.
- **Unsupported:** intentionally omitted; the app reports an item-level reason.
- **Pending:** implementation or required evidence is incomplete.

“Unit verified,” “mock verified,” and “live-read verified” must never be shortened to “hardware verified.” As of 2026-07-16, **no live setting mutation is hardware verified**. Tray Surface v2 and its deterministic tests passed the full non-live local gate. The corrected package is build/mount verified but was not installed or launched; a user-provided screenshot covers only the preceding installed v2 build and exposed the presentation defects corrected here.

## Tray Surface v2 evidence

| Contract | Automated/offscreen evidence | Manual status |
| --- | --- | --- |
| One status item, popover, and hosting controller | Factory/count/behavior tests verify one `.applicationDefined` surface and matching host bounds without constructing live AppKit presentation | Actual status-item click, anchor, arrow, material, and ghost-frame behavior pending |
| Fixed open-session viewport | Deterministic 0/1/3/10-profile, small-screen, scale, screen-change, state-change, and reopen tests pass | Installed multi-monitor/scale transition pending |
| Action disposition and handoff | Every action is mapped; stay-open cannot close; visible/key order, cancellation/failure, duplicate click, stale generation, and quit-only termination pass | Native focus-transfer timing and first responder pending |
| App-lifetime state/workflows | Dismiss/reopen task survival, deletion focus, persistent-window ownership, and synthetic permission suppression pass | Full keyboard and VoiceOver walkthrough pending |
| Bilingual rendering | 17 detached-host PNG/AX pairs pass size/privacy checks; English/Korean, light/dark, 680×480 minimum, large text, and one high-contrast appearance are represented | Real system text size, contrast, reduce-transparency, and complete accessibility tree pending |

## Platform

| Area | Target | Current evidence |
| --- | --- | --- |
| macOS | 14 Sonoma or later | Deployment target is 14.0. Tray Surface v2 passed full local `make verify` on 2026-07-15 with 326 default cases (130 XCTest plus 196 Swift Testing cases, six opt-in skips), zero failures, and no live flag. Earlier measured-height, permission, tray/editor, apply-reliability, header/editor, and 2026-07-11 gates remain historical evidence |
| Apple Silicon | arm64 | Default tests passed on the current Tray Surface v2 source. The opt-in live-read smoke tests passed on the preceding capture source on an Apple M5 Mac; the display gate covers both active displays and the legitimate online-but-inactive sleep state |
| Intel Mac | x86_64 | Current Swift/Xcode Debug/Release and packaged executable contain x86_64; physical Intel execution is pending |
| Distribution | Direct no-Developer-ID DMG | Current `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`, SHA-256 `567917f169e90799db177d0a5f22a8b13115cb30ed63f7e766fc4bb992ab35e3`, passed checksum, mount, metadata/resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID signature verification. It was not installed or launched. Earlier checksums remain historical; nothing is published and the Gatekeeper path remains pending |
| CI | GitHub Actions | UI-hardening commit `5f0cabc` passed full `make verify` and unsigned-package upload in [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967). Initial failure run `29154880831` and repair run `29155207923` remain historical Swift 6.1 compatibility evidence |
| App Store | Not required | No sandbox/App Store claim |
| Signing/notarization | Optional | App is ad-hoc signed for integrity only; no Developer ID identity or notarization exists |

## App, profiles, and safety engine

| Area | Capability | Status and evidence |
| --- | --- | --- |
| App | Background/menu-bar-only lifecycle | `LSUIElement` and the app-owned `NSStatusItem`/`NSPopover` source are build/package verified. The current DMG was not installed or launched. Historical installed interactions verify only the superseded surface and Settings/store behavior they directly exercised |
| App | Login item | Default-on `SMAppService.mainApp` registration succeeded and BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it, re-enable restored enabled status, and final cleanup opted out with only disabled BTM history. Approval-required/retry and actual login-at-boot after a reboot remain pending |
| App | English/Korean UI | Integrated lint passed key parity, duplicate-key, placeholder, and statically discoverable-key checks. Exact runtime localization tests cover both bundles. The [current-source audit](MANUAL-UI-AUDIT-2026-07-14.md) visually reviewed six English and six Korean states, including long strings and 680×480 layout; complete interactive and linguistic-quality review remains pending |
| App | Accessibility | Current source contains icon labels/help, non-color state and validation text, deterministic deletion focus targets, shortcuts, and remaining-time metadata. Detached `NSHostingView` exposes only its root accessibility group, so the 17 current metadata files record declared labels and that limitation rather than claiming a complete tree. Full VoiceOver speech/rotor/focus, keyboard-only, first responder, contrast, transparency, and real macOS text-size behavior is not verified |
| App | System, About, and diagnostics presentation | Profiles/System/About is the primary navigation. System keeps login and permission guidance visible and describes diagnostics as optional troubleshooting; an on-demand advanced sheet retains browsing, refresh, and confirmed clearing. About keeps repository, issue, MIT license, and privacy links. Current English/Korean System and diagnostics screenshots plus read-only AX logs passed static review; link activation and clear actions were not invoked |
| Profiles | CRUD, ordering, selection, metadata, per-group/per-option inclusion | Mock verified at the storage/domain boundary. Each tray profile has a named Delete control whose confirmation expands inside the fixed open-session viewport and single scroll region. Cancel/`Esc` leaves storage untouched; confirmation focuses the next profile or empty state. A historical fresh install created one schema-v1 Ready profile; current v2 interaction is pending |
| Profiles | Saved/draft editing, replacement protection, and metadata merge | Deterministic draft, dirty-Apply, and app-integration cases verify save/discard/cancel before planning, save-failure preservation, and latest stored-profile use. The installed same-window check preserves a valid unsaved draft, selection, Save availability, and field focus across 980→680→980 |
| Profiles | Current-settings refresh into draft | Unit/source verified: the read-only snapshot result replaces draft settings only and requires explicit save before persistence; no current-tree manual snapshot walkthrough |
| Profiles | Inclusion/disclosure and typed setting-value editor | Full-gate source/unit verified: group/option inclusion is independent from disclosure; collapsing preserves values, common controls use typed pickers/toggles/sliders, and snapshot-only values are read-only. The dense `Form` was replaced with wider card groups and padded option rows beside regular-size Include controls; refreshed English/Korean Audio-row screenshots plus AX logs confirm the text-compression regression is absent. Pure field validation covers group leaves, primary-display uniqueness, required values, ranges, modes, Wi-Fi name bytes, addresses, masks, DNS, ports, and input bounds. Current static standard/minimum/large-text editor layouts passed; interactive keyboard/VoiceOver and state-preserving resize remain pending |
| Profiles | Value-first summaries, icon preservation, and technical disclosures | Unit verified; current v2 English/Korean detached-host evidence covers long names, readiness text, symbols, overflow, and destructive state. Actual v2 status-item/popover and profile-row action click-through remain pending |
| Profiles | Versioned JSON, schema 0→1 migration, semantic/resource limits | Mock verified |
| Profiles | Atomic primary/backup, corruption quarantine/recovery, local file permissions | Mock verified with temporary-file tests, including 0700 directories and 0600 managed files; sudden-power-loss durability is not claimed |
| Profiles | Import/export | Existing size/schema/semantic, duplicate-ID, source-protection, and no-overwrite behavior is mock verified. The full gate passed deterministic import/codec coverage proving unsupported applicability is normalized on decode/import while values are preserved |
| Snapshot | Detected/storable/unreadable/permission-required/unsupported internal classification | Internal classification remains mock verified and concrete adapters were live-read verified on one Apple Silicon Mac. Current user-facing capture results include saved applicable leaves and actionable permission-required items only; snapshot-only, unreadable, and unsupported evidence remains available to sanitized diagnostics but does not turn capture into a noisy partial-result card. The network adapter no longer reads or emits always-unsupported service order. Runtime display/audio/network identifiers remain absent from retained presentation state |
| Snapshot | Unsupported applicability normalization | Full-gate unit/mock verified and idempotent for capture, decode, local store, import, and planning. Display rotation/active state and administrative IPv4/DNS/proxy values remain stored but excluded; unsupported-only groups produce no applicable payload. All cases use synthetic values |
| Readiness | Ready/Partial/Unavailable manual plan state | Existing adapter/readiness behavior is mock verified and combined read-only fact collection was live-read verified. Current manual readiness ignores dormant legacy conditions, uses normalized applicability, and no longer lets historical applied/failed result state permanently mask a refreshed calculation; deterministic/app-source coverage is present |
| Readiness | Legacy condition compatibility | Core all/any/inverted evaluation remains unit/mock verified and data remains round-trip compatible. Condition editing is absent, and existing/imported conditions are deliberately dormant and non-blocking for current manual readiness, preview, and Apply. Historical choice/input-validation tests are compatibility evidence, not a current UI feature |
| Apply | Normal/force preview, omissions, zero-operation rejection, no-op filtering | Mock verified; fresh snapshot profile produced a zero-operation plan with Apply and Force Apply disabled, with no mutation |
| Apply | State-aware primary action and friendly preview | Implemented with one row action: Ready + operations opens normal Apply; Partial + executable operations opens Apply Available in the same slot; zero-operation, preparing, lock, confirmation, and unavailable reasons remain textual/non-color. Cached readiness can remain usable during refresh, duplicate preparation is blocked per profile, and ellipsis/separate availability review/manual refresh remain absent. Deterministic presentation cases and current static Ready/Partial overview evidence are present; no current-tree click-through or live execution |
| Apply | Dirty-draft and pre-execution stale-plan defense | Existing stale-plan recapture/comparison is mock verified. Current source resolves same/other dirty drafts before preparing, then reloads profile/system state and execution-relevant rollback payloads; save failure/cancel cannot proceed. Pure decision cases are present; no live execution |
| Apply | Immediate result and post-apply read-back | Full-gate unit/mock verified as a compact result card plus itemized detail with success/failure/skipped/unsupported/rollback/not-verified counts. After execution or display Keep, fresh planning marks a succeeded operation that remains required—or cannot be read because capability, snapshot, fatal validation, or infrastructure preparation is unavailable—as not verified while keeping intentional force omissions separate. Rollbacks reconcile by operation UUID, so same-key operations are not conflated and successful rollback does not erase an initiating failure. This is mock/read-back evidence, not hardware mutation proof |
| Apply | One active transaction, deterministic order, fatal reverse rollback | Mock verified, including rollback failure separation |
| Apply | 15-second high-risk confirmation and protected rollback token | Mock verified with temporary apply, confirmation commit/failure, timeout, revert, and rollback; real display mutation not run |
| Diagnostics | Redaction and rotating local JSONL files | Mock verified for secrets, exact location, SSID, IP host portions, home paths, permissions, rotation, concurrency, and clearing |
| Diagnostics | Browse/refresh/clear from System | Implemented with sanitized events under Application Support. The feature is presented as optional troubleshooting and opens in an advanced sheet from System. English/Korean disabled synthetic presentation passed screenshot/AX review; refresh/clear and real persisted-event flows remain pending |

## Non-live UI-hardening evidence recorded on 2026-07-12

The historical header/editor follow-up passed full local `make verify` with 215 tests: 112 XCTest cases with five opt-in skips plus 103 Swift Testing cases with one opt-in skip. Across both frameworks, five were read-only hardware cases and one was a Keychain-write case. The 56 presentation-specific cases comprised 29 draft XCTest cases and 27 presentation/condition Swift Testing cases. Localization lint covered English/Korean key parity, duplicate keys, format placeholders, and statically discoverable localized UI keys. Swift and universal Xcode Debug/Release, Analyze, package, checksum, mounted resources/architectures, and ad-hoc signature classification passed.

No live flag was set. This evidence includes no screenshot walkthrough, full keyboard or VoiceOver run, TCC grant/deny action, login-item state mutation, hardware read, Keychain write, setting apply, or rollback. The then-current local DMG SHA-256 was `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967), but that CI artifact predates the local header/editor follow-up.

## Apply-reliability evidence verified on 2026-07-14

Integrated non-live `make verify` passed lint/localization policy; 290 default cases (124 XCTest with five opt-in skips plus 166 Swift Testing cases with one opt-in skip), zero failures; Swift Debug/Release; universal Xcode Debug/Release; Analyze; package/checksum; mounted metadata/resources/`x86_64 arm64`; and ad-hoc/no-Developer-ID signature classification. Across both frameworks, five skips are read-only hardware cases and one is a Keychain-write case. Separately, `git diff --check` passed. Deterministic synthetic cases cover state-aware normal/available-items selection, cached refresh and duplicate preparation, dirty-Apply decisions, complete/partial/failure capture summaries, read-back unavailable/not-verified result classification, UUID-based rollback reconciliation, field-specific validation, unsupported applicability normalization and idempotence, storage/import boundaries, adapter capture defaults, and immediate input-preference read-back disagreement. Existing mock transaction tests continue to cover normal/force planning, omissions, stale-plan defense, fatal reverse rollback, and display safety.

The verified artifact is `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`, SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`. It is build/mount verified only; it was not installed, quarantined, launched, or mutated against hardware. No push or new CI run was performed.

This historical apply-reliability evidence is unit/mock/read-back only. At that milestone it did not include a live Apply, actual display/audio/network/input mutation, hardware rollback, a new live read, UI automation, full VoiceOver, TCC grant/deny, Keychain write, physical Intel execution, Developer ID signing, notarization, or release publication.

## Final-source synthetic and installed UI audit on 2026-07-15

The DEBUG-only host used synthetic fixtures, a temporary store, empty system/apply dependencies, disabled permission requests, and public-action suppression verified by `UIAuditSafetyTests`. The [audit report](MANUAL-UI-AUDIT-2026-07-14.md) records 16 rendered PNGs and 16 read-only AX logs from the Xcode Debug app bundle. All were visually/structurally inspected and privacy scanned. The four 2026-07-15 additions show the current complete bilingual inline deletion/capture feedback and regular/minimum editor feedback states. A separately authorized installed interaction used `DESK_SETUP_LIVE_UI_TESTS=1`, a complete preflight backup, and byte-for-byte rollback; it changed no system setting.

| Requested state | Source/test evidence | Remaining boundary |
| --- | --- | --- |
| Ready normal Apply | `ApplyWorkflowPresentationTests` verifies the normal primary action | No current-tree click-through |
| Partial Apply Available with operation plus omission | `ApplyWorkflowPresentationTests` verifies force preview keeps the display operation and separates the DNS omission | No live execution |
| Unavailable and no-op | `ApplyWorkflowPresentationTests` verifies distinct disabled reasons; overview evidence includes disabled and no-op rows | No current v2 popover interaction |
| Dirty draft Save/Discard/Cancel and Apply | `DirtyApplyProtectionTests` verifies same/other-profile targets, save success/failure, cancel, and latest draft use | No manual dialog/keyboard walkthrough |
| Actionable capture permission result | Current `ProfileCaptureSummaryBuilderTests` prove snapshot-only, unreadable, unsupported, and runtime-identifier evidence is omitted while a permission-hidden Wi-Fi name remains value-free and actionable. Injected app tests cover authorization-request and System Settings-open routing without live TCC actions, including the invariant that the persistent app System tab is requested before delayed system UI. The scoped installed interaction showed the privacy explanation and a persistent app System window at 100 ms and 600 ms after Continue | macOS resolved Location as already allowed, so the exact permission-result-card action and full denied/granted TCC matrix remain pending |
| Inline validation | Tests verify field identifiers and validation rules; English/Korean screenshots and AX logs expose non-color summary, first issue, and reveal action | Focus movement after activating the action is pending |
| Success/partial/failure/rollback/not-verified results | `ApplyWorkflowPresentationTests` verifies counts, UUID rollback reconciliation, unavailable read-back, and profile readiness mapping | No result sheet walkthrough |
| Tray deletion | Exact-ID request/cancel/confirm, fixed viewport, focus recovery, and normal/confirmation overflow are deterministic-test verified; current English/Korean detached-host evidence shows complete actions | Installed v2 Esc, Cancel, Confirm, and full keyboard traversal remain pending. Historical `MenuBarExtra` interaction is not reused |
| Responsive Settings | Breakpoint and owned-window geometry tests cover 760-point switching, resizable style, 680×480 minimum, and stable window ownership | Installed 980→680→980 preserved selected row, valid dirty draft, focus, Save availability, and expanded Audio state |
| Collapsed/expanded groups and options | `DirtyApplyProtectionTests` verifies `DisclosureState` never changes inclusion or values; standard/minimum/large-text editor evidence covers expanded Display/Primary content and fixed actions | Installed same-window disclosure preservation passed; full option-by-option walkthrough remains pending |
| English/Korean and long strings | Catalog lint and exact runtime-bundle tests pass; eight English and eight Korean rendered states passed static review, including current 680×480 minimum | Interactive linguistic-quality audit remains pending |
| Keyboard and accessibility structure | Sixteen nonempty localized AX logs confirm labels, values, descriptions, validation metadata, and de-duplicated profile rows | Scoped field-focus preservation passed; full keyboard-only order and VoiceOver behavior remain pending |

## System capabilities

| Group | Capability | API/mechanism | Status and evidence |
| --- | --- | --- | --- |
| Display | Active display discovery and stable identity | Public Core Graphics/ColorSync | Mock verified and current-source live-read verified on one Apple M5 Mac. The gate preserves count/identity/mode checks when active and verifies a typed nonfatal empty snapshot when the online session display is asleep |
| Display | Primary display and topology/origin | Core Graphics display configuration | Mock verified; live mutation not run |
| Display | Mirroring | Core Graphics display configuration | Mock verified; live mutation not run |
| Display | Logical/pixel mode and refresh rate | Core Graphics display modes | Mock verified; live mutation not run. Read-only snapshots now carry typed ephemeral supported-mode catalog entries for the editor picker; this catalog is runtime context and is not persisted in profile JSON |
| Display | Temporary apply, confirmed commit, and rollback | Core Graphics app/session configure scopes | Mock verified: apply is app-only, **Keep Changes** re-commits session-only, and rollback is session-only; live mutation/timeout/app-exit behavior not run |
| Display | Rotation mutation | No safe public implementation | Unsupported; rotation is snapshot-only |
| Display | Activation/deactivation mutation | No safe public implementation | Unsupported; active state is snapshot-only |
| Audio | Device/UID/scope/default/control discovery | Public Core Audio | Mock verified and live-read verified on one Apple M5 Mac |
| Audio | Default input/output/system output | Public Core Audio properties | Mock verified; live mutation not run |
| Audio | Output scalar volume/mute | Capability/settable Core Audio properties | Mock verified; unsupported controls become item omissions; live mutation not run |
| Audio | Microphone capture | Not used | Unsupported and not requested |
| Network | Interfaces, link, IP/subnet, gateway, DNS, services, IPv4/proxy/order snapshot | CoreWLAN, SystemConfiguration, getifaddrs | Mock verified and live-read verified on one Apple M5 Mac; Ethernet-specific manual coverage pending |
| Network | Wi-Fi power | CoreWLAN | Mock verified; live mutation not run |
| Network | Saved-network association | CoreWLAN/macOS-held saved-network credential | Mock verified: target saved profile/access is preflighted and current association must have a safe rollback target; no password enters profiles/operations/logs; live mutation not run |
| Network | SSID read | CoreWLAN with authorization-aware result | Powered-on nil SSID is treated as ambiguous/unavailable, never proof of safe disassociation; mock verified and live adapter smoke passed, but denied/granted value matrix is pending |
| Network | DHCP/static IPv4, DNS, proxy, service-order mutation | No authorization/rollback-safe implementation | Unsupported; values may be snapshotted but mutation is omitted |
| Input | Pointer speed and natural scrolling snapshot/apply | CFPreferences, undocumented global keys | Experimental; mock verified, live-read verified, live mutation not run |
| Input | Key repeat, repeat delay, standard F-key snapshot/apply | CFPreferences, undocumented global keys | Experimental; mock verified, live-read verified, live mutation not run |
| Input | Immediate write read-back | CFPreferences snapshot after synchronize | Deterministic injected tests require the freshly read value to match; disagreement returns failure instead of success. This is immediate adapter read-back/mock evidence, not proof of perceived hardware behavior |
| Conditions | Display, audio input/output, USB/hardware, SSID, Ethernet, IP/CIDR | Core evaluator plus public read-only discovery | Mock verified; combined discovery live-read verified |
| Conditions | Authorized recent location | Core Location cached/one-shot request | Mock verified; no continuous tracking; denied/granted and stale-location manual matrix pending |
| Secrets | `SecretStore` generic-password implementation | Security framework, device-only after-first-unlock accessibility | Mock verified with synthetic bytes; live Keychain write deliberately not run |

## Explicitly unsupported features

- Automatic or background profile switching
- Logitech Options+, Razer Synapse, or other vendor profile control
- Vendor-specific DPI/button mapping or keyboard firmware settings
- Direct editing of Karabiner-Elements or any third-party app configuration
- UI scripting of System Settings or third-party apps
- Private macOS APIs, arbitrary shell execution, application telemetry, or cloud services
- Administrative network mutation without a public authorization and rollback design

## Historical read-only evidence recorded on 2026-07-11

The historical 2026-07-11 local `make verify` gate passed with 158 tests: 83 XCTest and 75 Swift Testing cases. Six opt-in cases skip by default: five read-only hardware tests and one Keychain-write test. On 2026-07-14 the current capture-permission source reran `DESK_SETUP_LIVE_READ_TESTS=1`; display, audio, network, input, and combined condition-context tests all passed on an Apple M5 Mac running macOS 26.5.2, including the online-but-inactive display sleep state. These tests call only capability/snapshot/read paths. No personal device identifier, SSID, IP address, or location is recorded in the repository.

## Historical local package evidence recorded on 2026-07-11

- Universal Debug/Release builds and the packaged executable contain `arm64 x86_64`.
- The post-fix no-Developer-ID DMG checksum is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; mounted layout, bundle metadata, icon, English/Korean resources, and ad-hoc app signature passed the checked-in verifier.
- Downloaded CI artifact ID `8249295840` verified its checksum file and CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; it differs from the local checksum because the DMGs are not byte-for-byte reproducible.
- The recorded local-DMG fresh copy to `/Applications` launched background-only/menu-bar-only; the popover and Settings rendered in Korean, and an accessibility label passed inspection. This is baseline evidence, not a current UI-tree walkthrough.
- The fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. Its zero-operation plan kept Apply and Force Apply disabled.
- Default-on `SMAppService` registration succeeded and BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it, re-enable restored enabled status, and final cleanup opted out with only disabled BTM history.
- The local copy did not exercise quarantine/Gatekeeper, approval-required/retry states, or actual login-at-boot after a reboot. No full VoiceOver/keyboard, import/export, permission, or live-mutation procedure was run.

Coverage still absent:

- An external display, mirrored pair, display mode change, and unplug/replug identity matching
- An audio device without software volume/mute and a device hot-plug sequence
- Ethernet and both Wi-Fi permission-denied and permission-granted cases
- A physical Intel Mac
- Login-item approval-required/retry paths and actual login-at-boot after a reboot
- A downloaded/quarantined Gatekeeper install
- Any live setting apply or rollback
- A live Keychain round trip
- A current-tree synthetic-data screenshot/layout walkthrough and full keyboard/VoiceOver/focus/contrast/text-size audit

## Tray and settings refinement evidence recorded on 2026-07-16

The final non-live gate passes 339 default cases (132 XCTest plus 207 Swift Testing, six opt-in skips), Swift/Xcode Debug and Release, Analyze, and universal mounted-package verification. Current local DMG SHA-256 is `567917f169e90799db177d0a5f22a8b13115cb30ed63f7e766fc4bb992ab35e3`; it was not installed or launched.

| Capability | Implementation boundary | Current evidence |
| --- | --- | --- |
| Tray reopen geometry | Fixed `contentSize`; zero-origin hosting frame/bounds before and after show; post-show generation-scoped top-scroll request; first content block owns the anchor; one internal scroll view | Deterministic AppKit/SwiftUI tests cover deliberately displaced geometry, stale attach rejection, and 20 open/close cycles. A user-provided installed screenshot exposed the former anchor-only spacing row; refreshed detached evidence shows it removed. Actual menu-bar anchor, popover material, dismissal, and corrected visible reopen behavior remain manual |
| Persistent Settings/Profile Edit | App-lifetime controllers; red-close orders out; visible/key/front completion precedes tray close; shared `.regular`-while-visible/`.accessory`-when-hidden coordinator | Deterministic tests cover 10 reopen cycles per destination, two-window activation ownership, non-key recovery, cancellation, coalescing, stale completion, and unsaved-root identity. Native app/Space switching and window ordering after an installed click remain manual |
| Settings profile actions | Fixed Revert/Save footer; no current-settings draft refresh action; tray Capture creates the current-state profile | Source policy and refreshed five-fixture detached evidence cover the simplified action bar. Save/revert behavior remains deterministic-test verified; corrected native rendering is manual |
| Status-item profile indicator | Fresh enabled Ready plus known zero-operation match only; applying state wins; invalid/deleted/stale values fall back | Unit/AppKit tests cover fallback symbol, long name, preferred selected match, applying, failure, and deletion. A live status-item label was not inspected |
| Audio input volume | Public Core Audio input scope with snapshot/validate/plan/apply/rollback; isolated unsupported/non-settable/hot-plug behavior | Deterministic adapter tests pass. No live input-volume mutation or hardware rollback was run |
| Display color mode | Current Core Graphics color-space name is session-only read evidence; it is not a ColorSync profile, HDR state, or pixel encoding; no public rollback-safe mutation path | Synthetic editor evidence shows `Synthetic sRGB` and the unsupported reason. No vendor API, private API, or System Settings automation exists |
| Ethernet/Wi-Fi service IPv4 | Portable kind plus service name plus interface type identity; public SystemConfiguration read; DHCP/manual validation | Synthetic snapshot/ambiguity tests pass. Apply is disabled pending an authorized rollback-safe implementation; unrelated Wi-Fi operations are preserved. No real service or address appears in evidence |
| Simplified editor projection | Alias/symbol/enabled and Display/Audio/Network only; saved Wi-Fi uses the current public read-only catalog; description/conditions/Input and legacy leaves round-trip but normalize out of apply | Migration/normalizer/catalog tests and five detached PNG/AX pairs cover standard, 680×480 minimum, accessibility large text, Korean, and dark mode. Detached Korean evidence exercises catalog strings but native SwiftUI localization context and complete linguistic review remain manual |

For any later audio hardware procedure, test input and output volume separately and only when the adapter reports the corresponding scope settable. For network review, confirm service identity ambiguity disables only that service's IPv4 row; do not attempt static address mutation. Color-mode verification is read-only until a public rollback-safe capability exists.

## Manual hardware verification procedure

Every record must include date, macOS/app commit, broad hardware class with serials redacted, expected/actual result, rollback result, sanitized diagnostic event IDs, and tester. Never record a real SSID, exact location, IP host address, password, serial number, or raw exported profile.

### Shared preflight for every mutation

1. Obtain explicit approval for the named mutation and use a local build from a clean verified commit. Never run the procedure in CI.
2. Connect only the devices under test. Capture a read-only “Before” profile and independently record the original state in System Settings without sensitive values.
3. Confirm a manual recovery route: System Settings for audio/network/input; a second usable display or Screen Sharing for display tests; known saved Wi-Fi and Ethernet fallback for network tests.
4. Apply only one setting group and the smallest reversible change. Use the app's preview; cancel if the plan contains an unexpected group, missing rollback data, or an ambiguous identity.
5. Verify the changed setting through the relevant macOS UI and a fresh read-only snapshot. Use **Revert Now** when the display safety prompt offers it; otherwise apply the “Before” profile, then verify the original state independently.
6. Redact the resulting evidence and update this matrix. A successful apply without a successful restore is a failed verification.

### Display procedure

Use a built-in display plus one external display where available. First test an origin-only change, then primary/mirroring/mode separately. Keep an independent screen/control path available. Verify the initial change is temporary/app-only; let the 15-second timer expire once and confirm restoration, test **Revert Now**, then repeat and choose **Keep Changes** to exercise the session-only confirmation commit. Finally restore the “Before” profile. Also verify quitting during the temporary-confirmation window restores state. Do not test rotation or activation; they are unsupported.

### Audio procedure

Use a device identified by Core Audio UID. Change one default role, then volume and mute only if the adapter reports each control settable. Verify independently in Control Center/System Settings and restore. If a device has no software volume/mute, verify that the preview omits only that item without failing unrelated audio settings.

### Network procedure

Ensure an alternate connection exists and the target SSID is already saved by macOS. Test Wi-Fi power and saved-network association separately; never enter or export a password. Confirm the plan omits association when target saved access cannot be preflighted, the current association cannot be restored, or a powered-on interface has an unreadable/ambiguous SSID. Verify permission denial affects only SSID-dependent behavior, then grant permission through normal macOS UI and retest read-only discovery. Restore the original network before ending. Do not test static IPv4, DNS, proxy, or service-order mutation; they are unsupported.

### Input procedure

Because these operations use experimental global preference keys, record the original pointer/scroll/key values first and test one value at a time. Verify in System Settings or observable input behavior, restore immediately, and log the exact macOS version. A version-specific mismatch keeps the row experimental/unverified.

### Keychain and platform procedure

Run the gated synthetic Keychain round trip only after explicit approval, then confirm the test item was deleted. It is separate from setting mutation evidence. Repeat the safe build, default tests, app launch, and read-only discovery on physical Intel hardware before changing the Intel row from cross-build only.
