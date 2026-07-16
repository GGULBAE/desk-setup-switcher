# Technical specification

## Status and target

This is both the implementation contract and a description of the current pre-release 0.1.0 architecture. A native Swift/SwiftUI menu-bar application, checked-in generated Xcode project, and Swift Package core/system/app targets exist for macOS 14 or later. Core and adapter behavior can be tested without launching the app or changing the host Mac.

The repository targets both `arm64-apple-macos14.0` and `x86_64-apple-macos14.0`. The apply-reliability Swift Debug/Release, universal Xcode Debug/Release, Analyze, and packaged builds passed local `make verify` on 2026-07-14. No physical Intel Mac has been tested. Scripts use a process-local `DEVELOPER_DIR` fallback when full Xcode is installed but `xcode-select` points to Command Line Tools.

## Module boundaries

```text
DeskSetupSwitcherApp (AppKit tray ownership, SwiftUI content, settings, permissions)
        |
DeskSetupPresentation (draft state, friendly summaries, action/input presentation)
        |
DeskSetupCore (models, validation, conditions, persistence, planning)
        |
DeskSetupSystem (display, audio, network, input, conditions, Keychain)
        |
Public macOS frameworks / explicitly isolated experimental preferences
```

UI code never calls Core Graphics, Core Audio, CoreWLAN, SystemConfiguration, or preference mutation directly. `DeskSetupPresentation` depends on Core value types but not SwiftUI, AppKit, or system adapters. `DeskSetupCore` has no dependency on UI frameworks and tests use mock adapters.

## Concurrency

- UI models and dialogs are `@MainActor`.
- One app-lifetime `ProfileEditorModel` owns the pure draft session across Settings-window presentation and responsive layout changes. Profile saves return typed asynchronous results before the UI changes draft state; current-state capture is initiated from the tray and creates a reviewable profile instead of replacing an open draft.
- A menu Apply request first resolves the pure dirty-draft decision. No profile or system planning begins until save/discard/cancel completes; per-profile preparation state prevents duplicate requests.
- Profile persistence and transaction coordination are actors.
- Only one apply transaction may run at a time.
- The UI can cancel before execution. In-flight transaction cancellation between planned operations is not currently exposed; fatal failures and explicit high-risk rollback are the implemented interruption/recovery paths.
- Read-only groups and condition sources are attempted in stable order, with per-source failure isolation and deterministic result ordering.

## Versioned profile format

The top-level document contains:

- `schemaVersion`
- `profiles`
- `selectedProfileID`
- `updatedAt`

Every profile uses UUID identity and contains metadata, ordered setting groups, per-option inclusion flags, typed setting payloads, typed conditions, and an optional last application summary. The legacy profile-level `isEnabled` field remains decodable but normalization forces it to `true`; it is no longer user-editable or an applicability gate. Dates encode as UTC ISO-8601 with nine fractional-second digits and decode both fractional and legacy whole-second values. Unknown future fields are ignored; unknown required enum values fail validation with a user-facing error.

`ProfileApplicabilityNormalizer` applies the current surface/support policy without changing the schema or deleting values. It forces legacy activation to true and excludes hidden Input, display origin/rotation/active state, audio system-output/mute, Wi‑Fi power/SSID, global IPv4, DNS, and proxy leaves, then derives group inclusion from visible included leaves. The transform is idempotent and runs at codec decode, local-store load/update, import, snapshot construction, and engine preparation boundaries. Thus older local or imported data cannot re-enable dormant mutations, while round trips retain their values.

Supported controls use typed ephemeral catalogs in `AdapterSnapshot`: display modes, ColorSync ICC profiles, Core Audio devices and writable volume controls, and exact network IPv4 rollback entries. The editor projects a control only when its catalog proves the complete vertical slice. Catalog entries, runtime URLs, device handles, display IDs, service IDs, and exact rollback dictionaries are not part of `DeskProfile` JSON.

### Import limits

- Maximum file size: 5 MiB
- Maximum profiles per document: 500
- Maximum conditions per profile: 100
- Maximum user-visible string length: 1,024 Unicode scalar values
- Profile IDs must be unique
- Imported data may not contain paths or URLs used for file access
- Unsupported future schema versions are rejected without modifying current data

Migrations are explicit sequential transforms. The original imported file is never overwritten.

## Local storage

Canonical data lives under `~/Library/Application Support/Desk Setup Switcher/`.

1. Encode and validate a complete replacement document.
2. Let Foundation's atomic file-write path create and replace a sibling temporary file.
3. Atomically replace the primary file; no stronger sudden-power-loss durability guarantee is currently claimed.
4. Retain the last known-good backup.
5. On decoding failure, copy the bad file to a timestamped `Quarantine` directory, restore the valid backup when possible, and otherwise start with an empty document while surfacing diagnostics.
6. Enforce 0700 on app-managed profile/quarantine directories and 0600 on primary, backup, and quarantined files.

Export uses a user-selected destination. Import reads only the selected file and passes the same size, schema, and semantic validation. Secrets use Keychain; profiles and backups never contain passwords.

## Profile draft and presentation state

`ProfileDraftSession` stores the selected saved profile, the user-editable draft, and an optional pending selection target. Dirty comparison covers name, description, symbol, settings/inclusion values, and conditions but deliberately ignores the legacy activation bit; last-application and storage metadata are not user-editable draft fields. Selection or replacement while dirty requires a typed save, discard, or cancel resolution.

Save marks the session clean only after `ProfileStore` returns the persisted value. Immediately before update, `ApplicationModel` reloads the authoritative profile and merges only editable draft fields so a stale draft cannot overwrite a newer last-application result or timestamp. The current Settings surface intentionally has no current-settings draft refresh action. Tray Capture rejects a snapshot without any usable payload and atomically creates plus selects the new reviewable profile in one store replacement.

Display, Audio, and Network groups are flat and always expanded; each visible option has its own Include switch. `VisibleSettingRegistry` declares nine setting kinds and requires capture/edit/validate/plan/apply/verify/rollback stages. Unsupported, missing, read-only, or ambiguous controls are absent. A single primary-display picker enforces exactly one included primary display. ColorSync targets require nonblank portable ID/hash values. Manual IPv4 validates each selected service's address, contiguous mask, and optional router with service-indexed field IDs. `ProfileDraftValidator` returns stable identifiers and typed required/range/format issues before save; the app maps them to English/Korean messages, invalid-state accessibility metadata, first-error focus, and useful valid-state hints.

The current app does not expose condition editing. Persisted and imported conditions remain part of dirty comparison and storage for schema round trips, but current manual readiness, preview, and execution deliberately pass the dormant condition policy as non-blocking. The pure evaluator and condition choice/input-validation utilities remain compatibility regression support, not a current Settings feature. `DeskSetupPresentation` also owns deterministic included-value summaries, technical-detail separation, operation preview text, the state-aware primary action, dirty-Apply decisions, capture summaries, result/read-back classification, and field validation. Localization and accessibility delivery remain app-layer responsibilities so device names and other user data are never treated as localization keys.

## Adapter contract

Every setting adapter exposes the same operations:

- `capability()`: supported, experimental, permission-required, temporarily unavailable, or unsupported, with reason
- `snapshot()`: read-only state plus detected/unreadable/permission-required/unsupported items
- `validate(desired, snapshot)`: typed issues and fatality
- `plan(desired, snapshot, mode)`: ordered no-op-filtered operations and rollback metadata
- `apply(operation)`: per-item result
- `confirm(operation)`: promote an already-applied temporary high-risk operation; most adapters use the no-op success default
- `rollback(operation)`: per-item rollback result using the operation's rollback payload
- `diagnostics()`: safe adapter-originated support entries

Adapters are injected by group identifier. Domain tests never construct live adapters. The app currently persists sanitized transaction/snapshot/storage/login/safety events; it does not yet aggregate every adapter's optional `diagnostics()` result.

## Apply transaction

```text
resolve dirty draft -> normalize profile -> snapshot capabilities -> validate -> plan
         -> capture backup -> apply low-risk operations in order
         -> success OR fatal error -> reverse rollback
         -> fresh read-only plan -> verified / not verified result
```

One primary menu slot selects normal mode for a Ready profile with operations and available-items/force mode for a Partial profile with executable operations. Normal mode rejects a plan with any included applicable unavailable item. Force mode records unavailable items as omissions and proceeds only after explicit UI confirmation. A plan with zero applicable operations is disabled with a distinct already-matches or no-available-work reason. A usable cached action can remain enabled during refresh, but transaction/protected-change locks and per-profile preparation always block execution. No-op comparisons are adapter-specific and tolerate insignificant numeric variance.

The preview is not an execution authorization for stale state. Before preview, a dirty editor draft must be explicitly saved, discarded, or left untouched by cancel; save failure never advances. Immediately before applying, the app reloads the current profile, recaptures readiness facts and adapter snapshots, and prepares a fresh plan under the dormant-condition manual policy. Generated timestamps and IDs may differ, but capabilities, readiness, validation, operations, omissions, payload values, and rollback values must be execution-equivalent. JSON object key ordering is canonicalized before payload comparison because encoder order is not state; non-JSON bytes and changed JSON values still require exact equality. Any meaningful difference replaces the request with a refreshed preview.

Each planned operation declares risk and fatal-on-failure behavior. The engine orders the stable groups as dormant input, Audio, Display, then Network, so protected rollback reverses connectivity before display. Within Display, atomic topology precedes ColorSync and rollback reverses that order. There is no general dependency graph in schema version 1.

A display topology operation first uses Core Graphics' app-only configure scope. Display ColorSync and Network IPv4 operations join the same protected transaction token, and the app presents a 15-second prompt. **Keep Changes** calls adapter confirmation hooks; timeout, Revert, red-close, termination, or failed confirmation restores completed protected operations in reverse order. Permanent display commit is not used before Keep. These paths are mock verified only.

After an execution without pending protected confirmation—or after Keep finalizes one—the app performs a fresh read-only preparation. `PostApplyVerificationResult` compares the originally executed group/key references with operations still required. A succeeded operation becomes `notVerified` when it remains required or when its group cannot be read back because capability, snapshot, fatal validation, or infrastructure preparation is unavailable; intentional force omissions and newly required operations remain separate. The compact result card and itemized detail present succeeded, failed, skipped, unsupported, rollback, rollback-failed, and not-verified counts without payload values. This verifies adapter-observable state only; it is not a claim about perceived hardware behavior.

Rollback presentation reconciles a rollback with its original result by operation UUID, not a shared group/key pair, so multiple same-key operations cannot replace each other. A successful rollback replaces only the matching prior success; an initiating apply failure remains a failure even when restoration succeeds. Likewise, a force apply with omissions or unsupported work remains an operational Partial result rather than being promoted to Applied merely because its executable operations succeeded.

The experimental input adapter also snapshots immediately after synchronizing a preference write. A value mismatch returns a failed item rather than success. Tests inject the read-back and are deterministic; no live input mutation has been run.

A failure is fatal only when continuing could create an inconsistent or unsafe configuration. Because an adapter can partially mutate before reporting failure, a fatal failing operation with rollback data is conservatively rolled back before earlier completed operations are reversed. Rollback failure is recorded separately and never replaces the original error.

## Capability and permission behavior

Capabilities are values, not thrown control flow. Permission denial produces an unavailable item and leaves unrelated groups operational. The app explains location use before its explicit permission action; stored legacy location conditions remain decodable but do not participate in current manual readiness or Apply. A complete SSID-triggered permission UX matrix is still pending. Login-item UI presents the app's desired setting separately from macOS registration status and emphasizes only mismatch/approval/error states. This presentation does not alter TCC or `SMAppService` semantics. Listing or selecting a Core Audio input device does not start microphone capture and must not request microphone permission.

## Stable device identity

- Display: UUID when available plus vendor/model/serial, built-in flag, and a conservative fallback fingerprint; runtime display IDs are session-only.
- Audio: Core Audio device UID; names are presentation only.
- Network: interface BSD name plus interface type; SSIDs are condition values, not credentials.
- USB/hardware: stable registry attributes available through public IOKit APIs, with capability reasons when identity is ambiguous.

Ambiguous matching never silently chooses a device. It produces a validation issue that the user can resolve.

For Wi-Fi, CoreWLAN's powered-on `nil` SSID is also treated as ambiguous/unavailable rather than “not associated,” so it cannot become a disassociation rollback assumption. Saved-network association requires a read-only preflight of the target saved profile/access and, when currently associated, a preflighted rollback association. If either side is not safely restorable, the switch is omitted.

## Logging and diagnostics

Structured local log entries contain timestamp, severity, component, safe event code, and a redacted summary. The redactor removes secrets, exact location, SSIDs where diagnostics do not need them, IP host portions, filesystem home paths, and Keychain material. Logs rotate by size and count. There is no remote logger and no application-owned outbound network request.

## App lifecycle

`LSUIElement` requests an accessory/menu-bar lifecycle. Production owns one `NSStatusItem`, one `.applicationDefined` `NSPopover`, and one `NSHostingController`; SwiftUI supplies contained tray content but does not own the surface lifecycle. `TrayGeometry` selects a 368-point-wide viewport and an empty, single-profile, compact, or capped-overflow height clamped to the active screen. `TrayOpenSessionGeometry` freezes that viewport for the open generation. The root ignores the native container's horizontal safe area and then applies exactly one symmetric 16-point content inset; an injected asymmetric-safe-area raster test protects this contract. It has no full-surface material and one internal `ScrollView`, so later banners, inline confirmation, async results, localization, and text-size changes cannot resize the outer popover.

`TrayActionRouter` is the only close/order-out boundary. Every `TrayAction` declares `stayOpen`, `handoff(destination)`, or `terminate`. Stay-open execution receives no surface reference. Handoff presents an app-lifetime Settings/workflow window, awaits visible and key state, checks that the originating generation is still current, then closes. Identical in-flight actions coalesce; failed/cancelled destinations leave the tray open; old completions cannot close a reopened tray. The status-item owner installs scoped outside-mouse and app-deactivation dismissal monitors only while open. Esc is handled by the root command. No global key monitor, event injection, UI automation, or arbitrary presentation delay is used.

App-lifetime controllers own deletion/focus intent, capture phase/task, permission task, dirty-draft decisions, apply preview/safety/result work, and destination errors. Popover disappearance does not cancel or duplicate these operations. Persistent `NSWindowController` + `NSHostingController` surfaces handle Settings, permission, dirty capture/apply, preview, safety confirmation, and result details. Settings retains its 680×480 minimum and shares navigation/editor objects across tray focus changes. `ApplicationWindowActivationCoordinator` registers every visible destination, switches to `.regular` only for the first, keeps ordinary app/window-cycle behavior until the last explicit hide, and then restores `.accessory`; failed/cancelled presentation unregisters defensively.

Profile rows expose one state-aware Review slot and direct Edit. Ready selects Review; Partial with executable operations changes the same button to Review Available. These actions open a persistent preview and never mutate settings. The separate Apply Profile confirmation repeats read-only preparation, starts the adapter transaction only when execution-equivalent, and otherwise returns to a visibly marked refreshed review. Rejected confirmation guards surface a workflow error. No ellipsis, separate availability review, or manual-refresh control is present. Readiness refreshes automatically when the menu opens, and old applied/failed outcomes are retained in the result presentation rather than permanently overriding new readiness. Apply results appear as a compact menu card with a Details sheet.

Direct Edit and general Settings select the shared navigation tab, show the owned window, and activate the accessory app; direct Edit also routes dirty-draft replacement through save/discard/cancel. The same protected decision now precedes Apply. The app owns profile draft state above the hosted Settings view and prompts save/discard/cancel before ordinary termination when the draft is dirty; an active apply transaction or pending protected confirmation retains termination deferral and triggers rollback. A historical 2026-07-15 installed interaction verified the window is AX-resizable and preserves selection, draft value, focus, and Save availability across 980→680→980; it predates the flat editor. `SMAppService.mainApp` controls login-at-launch; registration failure remains visible and nonfatal. Baseline default-on registration succeeded, Background Task Management reported `[enabled, allowed, notified]`, UI opt-out disabled it, and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history. Current-tree approval-required/retry states and actual login-at-boot after a reboot remain untested.

## Testing policy

- Unit: serialization, migration, validation, conditions, identity matching, CIDR, planning, redaction, error classification, rollback order.
- Presentation unit: saved/draft transitions, save/discard/cancel, external metadata refresh, snapshot-to-draft, inclusion-value preservation, included-value summaries, identifier disclosure, state-aware normal/available-items action selection, dirty-Apply decisions, typed capture summaries, read-back result classification, and field validation. Detected condition choices and typed condition input validation remain compatibility coverage, not current-UI coverage.
- Core/system unit and mock integration: applicability normalization/idempotence and store/import boundaries, supported display-mode catalog capture, immediate input read-back disagreement, success, partial force apply, dormant-condition manual planning, fatal failure and reverse rollback, rollback failure, denied permission, missing device, corrupt storage, and import/export.
- Live safe tests: opt-in read-only display, audio, network, input, and readiness-context discovery. Basic login-item registration/status/opt-out/re-enable is manually smoke tested; approval/retry/reboot paths remain pending.
- Live mutation: never in CI and never locally without an explicit environment flag and user action.

All fixtures use synthetic names, documentation-only addresses, and non-personal device identifiers.

The preceding header/editor follow-up passed full local `make verify` with 215 default tests: 112 XCTest cases with five opt-in skips and 103 Swift Testing cases with one opt-in skip. Across both frameworks, five were read-only hardware cases and one was a Keychain-write case. Its 56 presentation-specific cases comprised 29 draft XCTest cases and 27 presentation/condition Swift Testing cases. Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc signature classification passed; local DMG SHA-256 was `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [GitHub Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) provide historical remote CI/artifact evidence.

Tray Surface v2 passed integrated non-live `make verify` on 2026-07-15 with 326 default cases: 130 XCTest cases and 196 Swift Testing cases, with six opt-in skips and zero failures. Across both frameworks, five skips are read-only hardware cases and one is a Keychain-write case. Lint/localization policy, Swift Debug/Release, universal Xcode Debug/Release, Analyze, package/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification passed. Separately, `git diff --check` passed. The preceding measured-height and stable permission-handoff gates remain historical evidence.

The five read-only display/audio/network/input/readiness cases were rerun on the current capture-permission source and passed on an Apple M5 Mac running macOS 26.5.2. The display gate accepts the legitimate zero-active state while an online session display sleeps, verifies a typed nonfatal empty snapshot in that state, and retains full count, identity, mode, and item assertions whenever active displays exist. The historical fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups, and its zero-operation plan kept Apply and Force Apply disabled. There is no live mutation, hardware rollback, live Keychain write, physical Intel, latest permission-flow screenshot, full VoiceOver/keyboard, or TCC matrix evidence. Signing/notarization and release publication were not performed.

## Static and release verification

The canonical apply-plan follow-up passes 371 default non-live cases: 134 XCTest cases with five skipped opt-in cases and 237 Swift Testing cases with two disabled opt-in cases. Lint/localization policy, Swift Debug/Release, universal Xcode Debug/Release, Xcode Analyze, package/checksum creation, and mounted DMG metadata/resource/architecture/signature verification pass. The current no-Developer-ID DMG SHA-256 is `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`. No live mutation flag was set. The verified app replaced the `/Applications` bundle and passed read-only identity/version/architecture/signature checks; it was not launched after replacement.

Canonical commands are `build`, `test`, `lint`, `analyze`, `package`, `verify-package`, `verify`, and `clean` through the checked-in Makefile. `lint` includes source-policy checks and English/Korean key-parity, duplicate-key, format-placeholder, and static-localization-key validation. `verify` runs format/lint, tests, Swift and universal Xcode Debug/Release builds, Xcode Analyze, DMG creation, checksum validation, mounted-DMG inspection, and signature classification. The local closure gate runs `git diff --check` separately. CI performs no live discovery or system mutation. Initial run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue, and repair [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) remains historical compatibility evidence. UI-hardening commit `5f0cabc` passed full `make verify` and unsigned-package upload in [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967). Current push and CI results are recorded in the implementation handoff rather than predeclared here.

Packaging builds with automatic signing disabled, then ad-hoc signs the staged app. The verifier requires `Signature=adhoc`, no identity authority, and a structurally valid signature. The current universal `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` passed the mounted verification gate with SHA-256 `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662` and architectures `x86_64 arm64`; it was reinstalled but not launched after replacement. Earlier local and installed-interaction checksums remain historical in the completion ledger; downloaded CI artifact ID `8256718472` verified the earlier UI-hardening package at SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. These signatures provide code integrity only: the app has no Developer ID identity, no notarization, and no verified Gatekeeper trust path.

## Tray reopen and simplified editor specification

### Reopen invariants

- One status item, popover, hosting controller, root SwiftUI tree, and scoped event-monitor pair exist per application lifetime.
- Each open generation has a fixed `contentSize`; the hosting view frame and bounds origins are `(0, 0)` before and after show.
- Native horizontal safe-area values do not participate in SwiftUI content width; the root owns one symmetric 16-point inset.
- `trayDidOpen` creates the open generation; after `NSPopover.show`, `trayContentDidAttach` publishes that generation's top-scroll request. The root attaches the anchor ID directly to its first content block, so no anchor-only sibling contributes stack spacing.
- Reopening never reads prior content offset to calculate height and never adds a corrective padding or offset.
- The deterministic AppKit regression corrupts the host origin deliberately and checks 20 open/close cycles.

### Persistent destination invariants

- Settings and workflow controllers conform to presentation protocols and are strongly held by the app coordinator.
- A red-close event calls `orderOut` and returns `false` from `windowShouldClose`; controller, root model, and unsaved draft survive.
- Visible destinations participate in the ordinary application/window cycle through one shared coordinator. The first presentation sets `.regular`; hiding the last destination or failing presentation restores `.accessory`.
- Concurrent requests coalesce by presentation generation. Cancellation and completion pass through one exactly-once awaiter.
- Success means visible, key, and ordered front after application activation; only then may the action router close the tray.

### Status-item state

`TrayStatusItemState` is one of `noMatch`, `matching(profileID, symbolName, displayName)`, or `applying(profileID?, symbolName, displayName)`. A matching profile must be freshly ready, contain at least one included applicable payload, and have a known zero-operation plan. The selected profile wins ties. A legacy false activation value does not hide or block it. User names are trimmed and capped at 18 characters for the status item; full context remains in localized tooltip/accessibility text. Symbol lookup failure uses `square.stack.3d.up`.

### Visible profile document projection

| Area | Visible controls | Persisted but hidden/excluded controls |
| --- | --- | --- |
| Metadata | Alias and symbol | Legacy activation, description, and conditions |
| Display | Extended/mirrored output, primary display, per-display resolution/refresh, portable ColorSync ICC profile | Raw runtime ID, x/y origin, rotation, active state, HDR/pixel encoding/vendor modes |
| Audio | Default input, default output, input volume, output volume | System output UID and output mute |
| Network | Exact Ethernet/Wi‑Fi service target and DHCP/manual IPv4 | Wi‑Fi power/SSID, global IPv4, DNS, proxy, service order |
| Input | Nothing in the default editor | All legacy input values |

Hidden values remain meaningful document data. `ProfileApplicabilityNormalizer` excludes their options before readiness and planning, and repeated normalization is idempotent.

### Input volume

`inputVolume` is `SettingOption<Double?>`. Missing JSON decodes as `.excluded(nil)`. Included values must be finite in `0...1`. Snapshot calls the injected or public Core Audio input scalar getter for the default input UID and records unsupported or non-settable capability without failing default-device discovery. Planning requires a matched current device and writable input-volume element, stores the prior scalar as rollback, filters no-ops, and keeps missing or hot-plug failures typed and isolated.

### Service IPv4 and ColorSync ICC profiles

`NetworkServiceIPv4Settings` persists `NetworkServiceIdentity(kind, serviceName, interfaceType)` plus DHCP or manual configuration. The snapshot also carries the exact serialized IPv4 protocol dictionary for rollback, but that data remains session-only. The editor projects a row only when the portable identity resolves exactly once and rollback evidence exists. Apply uses Authorization Services plus `SCPreferencesCreateWithAuthorization`, re-resolves the service/protocol, checks lock/set/commit/apply/unlock, waits for dynamic-store change, and verifies exact DHCP/manual read-back. Network applies after display/audio and protected rollback restores network first. Authorization denial, timeout, mismatch, ambiguity, disappearance, and every preferences failure are typed and non-secret.

`ColorSyncProfileTarget` persists registered profile ID, SHA-256 of ICC file bytes, and display name. Runtime file URLs exist only in the current public ColorSync catalog. The adapter resolves exactly one ID/hash pair for the display, captures the existing custom-profile mapping, applies the new mapping, reads it back, and rolls the exact mapping back on failure or Revert. Display topology applies before color; rollback reverses that order. This contract is ICC profile selection only, not a claim about HDR, pixel encoding, vendor presets, or arbitrary “color mode.”
