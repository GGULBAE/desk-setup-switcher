# Technical specification

## Status and target

This is both the implementation contract and a description of the current pre-release 0.1.0 architecture. A native Swift/SwiftUI menu-bar application, checked-in generated Xcode project, and Swift Package core/system/app targets exist for macOS 14 or later. Core and adapter behavior can be tested without launching the app or changing the host Mac.

The repository targets both `arm64-apple-macos14.0` and `x86_64-apple-macos14.0`. The apply-reliability Swift Debug/Release, universal Xcode Debug/Release, Analyze, and packaged builds passed local `make verify` on 2026-07-14. No physical Intel Mac has been tested. Scripts use a process-local `DEVELOPER_DIR` fallback when full Xcode is installed but `xcode-select` points to Command Line Tools.

## Module boundaries

```text
DeskSetupSwitcherApp (SwiftUI, menu bar, settings, permissions)
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
- One app-lifetime `ProfileEditorModel` owns the pure draft session across Settings-window presentation and responsive layout changes. Profile saves and current-settings capture return typed asynchronous results before the UI changes draft state.
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

Every profile uses UUID identity and contains metadata, ordered enabled setting groups, per-option inclusion flags, typed setting payloads, typed conditions, and an optional last application summary. Dates encode as UTC ISO-8601 with nine fractional-second digits and decode both fractional and legacy whole-second values. Unknown future fields are ignored; unknown required enum values fail validation with a user-facing error.

`ProfileApplicabilityNormalizer` applies the current adapter support policy without changing the schema or deleting values. It forces display rotation/active state and administrative IPv4/DNS/web-proxy/secure-web-proxy leaves to excluded, then excludes any group with no remaining applicable leaf. The transform is idempotent and runs at codec decode, local-store load/update, import, snapshot construction, and engine preparation boundaries. Thus older local or imported data cannot re-enable unsupported mutations, while round trips retain the snapshot evidence.

Supported display modes are different: `AdapterSnapshot` may carry typed ephemeral `DisplayModeCatalogEntry` values from the read-only Core Graphics snapshot for a connected display. The editor uses this runtime catalog for a picker and can retain a saved-but-currently-unavailable mode, but catalog entries are not part of `DeskProfile` or profile JSON.

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

`ProfileDraftSession` stores the selected saved profile, the user-editable draft, and an optional pending selection target. Dirty comparison covers name, description, symbol, enabled state, settings/inclusion values, and conditions; last-application and storage metadata are not user-editable draft fields. Selection or replacement while dirty requires a typed save, discard, or cancel resolution.

Save marks the session clean only after `ProfileStore` returns the persisted value. Immediately before update, `ApplicationModel` reloads the authoritative profile and merges only editable draft fields so a stale draft cannot overwrite a newer last-application result or timestamp. A current-settings refresh calls the read-only snapshot coordinator, returns a typed snapshot result, and replaces draft settings without persisting until explicit save. Menu capture rejects a snapshot without any usable payload and atomically creates plus selects the new profile in one store replacement.

Group and option inclusion flags drive application only; app-layer disclosure sets independently control which group and option editors are expanded. Collapsing does not alter inclusion or payloads. Typed pickers, toggles, and semantic sliders are preferred over raw values, and normalized snapshot-only fields render read-only. A single primary-display picker enforces exactly one included primary display and preserves ambiguous legacy state as an explicit Choose/error state. Wi-Fi names validate as 1–32 UTF-8 bytes. `ProfileDraftValidator` returns stable field identifiers and typed required/range/format issues before save; the app maps them to English/Korean messages, invalid-state accessibility metadata, and first-error focus.

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

One primary menu slot selects normal mode for a Ready profile with operations and available-items/force mode for a Partial profile with executable operations. Normal mode rejects a plan with any included applicable unavailable item. Force mode records unavailable items as omissions and proceeds only after explicit UI confirmation. A plan with zero applicable operations is disabled with a distinct already-matches or no-available-work reason. A usable cached action can remain enabled during refresh, but transaction/display-safety locks and per-profile preparation always block execution. No-op comparisons are adapter-specific and tolerate insignificant numeric variance.

The preview is not an execution authorization for stale state. Before preview, a dirty editor draft must be explicitly saved, discarded, or left untouched by cancel; save failure never advances. Immediately before applying, the app reloads the current profile, recaptures readiness facts and adapter snapshots, and prepares a fresh plan under the dormant-condition manual policy. Generated timestamps and IDs may differ, but capabilities, readiness, validation, operations, omissions, payloads, and rollback payloads must be execution-equivalent. Any meaningful difference replaces the request with a refreshed preview.

Each planned operation declares risk and fatal-on-failure behavior. The engine orders by risk and then the stable input, audio, network, display group sequence. There is no general dependency graph in schema version 1. Display topology/mode operations are committed as one Core Graphics configuration where possible.

A display operation first uses Core Graphics' app-only configure scope. The engine retains its rollback token and presents a 15-second prompt. **Keep Changes** calls the adapter's `confirm` hook to re-commit the same configuration for the login session; timeout/revert rolls back, and a failed confirmation also triggers rollback. Permanent display commit is not used. These paths are mock verified only.

After an execution without pending display confirmation—or after Keep finalizes one—the app performs a fresh read-only preparation. `PostApplyVerificationResult` compares the originally executed group/key references with operations still required. A succeeded operation becomes `notVerified` when it remains required or when its group cannot be read back because capability, snapshot, fatal validation, or infrastructure preparation is unavailable; intentional force omissions and newly required operations remain separate. The compact result card and itemized detail present succeeded, failed, skipped, unsupported, rollback, rollback-failed, and not-verified counts without payload values. This verifies adapter-observable state only; it is not a claim about perceived hardware behavior.

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

`MenuBarExtra` hosts the primary UI. `LSUIElement` requests an accessory/menu-bar lifecycle. An app-owned `NSWindowController` and `NSHostingController` provide a genuinely resizable Settings surface for profile management, permissions, login item, sanitized diagnostics, import/export, licenses, and support status. The controller retains the window across tray focus changes, enforces a 680×480 content minimum, and shares the app-lifetime navigation/editor objects so responsive layout does not replace draft state. The header contains compact Capture plus icon-only Settings and Quit. Capture uses a typed complete/partial/failure summary; partial details remain in a compact banner and a result with no applicable leaf cannot create a profile.

Profile rows expose one state-aware Apply slot and direct Edit. Ready selects normal Apply; Partial with executable operations changes the same button to Apply Available. No ellipsis, separate availability review, or manual-refresh control is present. Readiness refreshes automatically when the menu opens, and old applied/failed outcomes are retained in the result presentation rather than permanently overriding new readiness. Apply results appear as a compact menu card with a Details sheet.

Direct Edit and general Settings select the shared navigation tab, show the owned window, and activate the accessory app; direct Edit also routes dirty-draft replacement through save/discard/cancel. The same protected decision now precedes Apply. The app owns profile draft state above the hosted Settings view and prompts save/discard/cancel before ordinary termination when the draft is dirty; an active apply transaction retains its existing termination deferral. A 2026-07-15 installed interaction verified the window is AX-resizable and preserves selection, draft value, disclosure state, focus, and Save availability across 980→680→980. `SMAppService.mainApp` controls login-at-launch; registration failure remains visible and nonfatal. Baseline default-on registration succeeded, Background Task Management reported `[enabled, allowed, notified]`, UI opt-out disabled it, and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history. Current-tree approval-required/retry states and actual login-at-boot after a reboot remain untested.

## Testing policy

- Unit: serialization, migration, validation, conditions, identity matching, CIDR, planning, redaction, error classification, rollback order.
- Presentation unit: saved/draft transitions, save/discard/cancel, external metadata refresh, snapshot-to-draft, inclusion-value preservation, included-value summaries, identifier disclosure, state-aware normal/available-items action selection, dirty-Apply decisions, typed capture summaries, read-back result classification, and field validation. Detected condition choices and typed condition input validation remain compatibility coverage, not current-UI coverage.
- Core/system unit and mock integration: applicability normalization/idempotence and store/import boundaries, supported display-mode catalog capture, immediate input read-back disagreement, success, partial force apply, dormant-condition manual planning, fatal failure and reverse rollback, rollback failure, denied permission, missing device, corrupt storage, and import/export.
- Live safe tests: opt-in read-only display, audio, network, input, and readiness-context discovery. Basic login-item registration/status/opt-out/re-enable is manually smoke tested; approval/retry/reboot paths remain pending.
- Live mutation: never in CI and never locally without an explicit environment flag and user action.

All fixtures use synthetic names, documentation-only addresses, and non-personal device identifiers.

The preceding header/editor follow-up passed full local `make verify` with 215 default tests: 112 XCTest cases with five opt-in skips and 103 Swift Testing cases with one opt-in skip. Across both frameworks, five were read-only hardware cases and one was a Keychain-write case. Its 56 presentation-specific cases comprised 29 draft XCTest cases and 27 presentation/condition Swift Testing cases. Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc signature classification passed; local DMG SHA-256 was `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [GitHub Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) provide historical remote CI/artifact evidence.

The current measured-height tray/responsive tree passed integrated non-live `make verify` on 2026-07-15 with 305 default cases: 129 XCTest cases and 176 Swift Testing cases, with six opt-in skips and zero failures. Across both frameworks, five skips are read-only hardware cases and one is a Keychain-write case. Lint/localization policy, Swift Debug/Release, universal Xcode Debug/Release, Analyze, package/checksum, mounted metadata/resources/architectures, and ad-hoc signature classification passed. Separately, `git diff --check` passed. The preceding 301-case stable permission-handoff gate remains historical evidence.

The five read-only display/audio/network/input/readiness cases were rerun on the current capture-permission source and passed on an Apple M5 Mac running macOS 26.5.2. The display gate accepts the legitimate zero-active state while an online session display sleeps, verifies a typed nonfatal empty snapshot in that state, and retains full count, identity, mode, and item assertions whenever active displays exist. The historical fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups, and its zero-operation plan kept Apply and Force Apply disabled. There is no live mutation, hardware rollback, live Keychain write, physical Intel, latest permission-flow screenshot, full VoiceOver/keyboard, or TCC matrix evidence. Signing/notarization and release publication were not performed.

## Static and release verification

Canonical commands are `build`, `test`, `lint`, `analyze`, `package`, `verify-package`, `verify`, and `clean` through the checked-in Makefile. `lint` includes source-policy checks and English/Korean key-parity, duplicate-key, format-placeholder, and static-localization-key validation. `verify` runs format/lint, tests, Swift and universal Xcode Debug/Release builds, Xcode Analyze, DMG creation, checksum validation, mounted-DMG inspection, and signature classification. The local closure gate runs `git diff --check` separately. CI performs no live discovery or system mutation. Initial run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue, and repair [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) remains historical compatibility evidence. UI-hardening commit `5f0cabc` passed full `make verify` and unsigned-package upload in [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967). Current push and CI results are recorded in the implementation handoff rather than predeclared here.

Packaging builds with automatic signing disabled, then ad-hoc signs the staged app. The verifier requires `Signature=adhoc`, no identity authority, and a structurally valid signature. The current universal `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` passed the mounted verification gate with SHA-256 `8bf4d547fae0df3cbe999db84e7be169b33d495b3993cf7c37f46ba37d6ea71d` and architectures `x86_64 arm64`; the installed `/Applications` executable matched it byte-for-byte. Earlier local and installed-interaction checksums remain historical in the completion ledger; downloaded CI artifact ID `8256718472` verified the earlier UI-hardening package at SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. These signatures provide code integrity only: the app has no Developer ID identity, no notarization, and no verified Gatekeeper trust path.
