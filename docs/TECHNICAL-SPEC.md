# Technical specification

## Status and target

This is both the implementation contract and a description of the current pre-release 0.1.0 architecture. A native Swift/SwiftUI menu-bar application, checked-in generated Xcode project, and Swift Package core/system/app targets exist for macOS 14 or later. Core and adapter behavior can be tested without launching the app or changing the host Mac.

The repository targets both `arm64-apple-macos14.0` and `x86_64-apple-macos14.0`. Current universal Debug/Release and packaged builds pass through local `make verify`; no physical Intel Mac has been tested. Scripts use a process-local `DEVELOPER_DIR` fallback when full Xcode is installed but `xcode-select` points to Command Line Tools.

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
- One app-lifetime `ProfileEditorModel` owns the pure draft session across Settings scene recreation. Profile saves and current-settings capture return typed asynchronous results before the UI changes draft state.
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

Save marks the session clean only after `ProfileStore` returns the persisted value. Immediately before update, `ApplicationModel` reloads the authoritative profile and merges only editable draft fields so a stale draft cannot overwrite a newer last-application result or timestamp. A current-settings refresh calls the read-only snapshot coordinator, returns a typed snapshot result, and replaces draft settings without persisting until explicit save.

`DeskSetupPresentation` also owns deterministic included-value summaries, technical-detail separation, operation preview text, menu action availability/reasons, detected condition choices, and typed IP/CIDR/location input validation. Localization and accessibility delivery remain app-layer responsibilities so device names and other user data are never treated as localization keys.

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
snapshot -> evaluate conditions/capabilities -> validate -> plan
         -> capture backup -> apply low-risk operations in order
         -> success OR fatal error -> reverse rollback -> result
```

Normal mode rejects a plan with any enabled unavailable item. Force mode records unavailable items as skipped and proceeds only after explicit UI confirmation. A plan with zero applicable operations is disabled. No-op comparisons are adapter-specific and tolerate insignificant numeric variance.

The preview is not an execution authorization for stale state. Immediately before applying, the app reloads the current profile, recaptures readiness facts and adapter snapshots, and prepares a fresh plan. Generated timestamps and IDs may differ, but conditions, capabilities, readiness, validation, operations, omissions, payloads, and rollback payloads must be execution-equivalent. Any meaningful difference replaces the request with a refreshed preview.

Each planned operation declares risk and fatal-on-failure behavior. The engine orders by risk and then the stable input, audio, network, display group sequence. There is no general dependency graph in schema version 1. Display topology/mode operations are committed as one Core Graphics configuration where possible.

A display operation first uses Core Graphics' app-only configure scope. The engine retains its rollback token and presents a 15-second prompt. **Keep Changes** calls the adapter's `confirm` hook to re-commit the same configuration for the login session; timeout/revert rolls back, and a failed confirmation also triggers rollback. Permanent display commit is not used. These paths are mock verified only.

A failure is fatal only when continuing could create an inconsistent or unsafe configuration. Because an adapter can partially mutate before reporting failure, a fatal failing operation with rollback data is conservatively rolled back before earlier completed operations are reversed. Rollback failure is recorded separately and never replaces the original error.

## Capability and permission behavior

Capabilities are values, not thrown control flow. Permission denial produces an unavailable item and leaves unrelated groups operational. The app explains location use before its explicit permission action and when a location condition is added; a complete SSID-triggered permission UX matrix is still pending. Login-item UI presents the app's desired setting separately from macOS registration status and emphasizes only mismatch/approval/error states. This presentation does not alter TCC or `SMAppService` semantics. Listing or selecting a Core Audio input device does not start microphone capture and must not request microphone permission.

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

`MenuBarExtra` hosts the primary UI. `LSUIElement` requests an accessory/menu-bar lifecycle. A Settings scene provides profile management, permissions, login item, sanitized diagnostics, import/export, licenses, and support status. The app owns profile draft state above the Settings scene and prompts save/discard/cancel before ordinary termination when the draft is dirty; an active apply transaction retains its existing termination deferral. A 2026-07-11 final-DMG baseline launched from `/Applications` background-only/menu-bar-only. `SMAppService.mainApp` controls login-at-launch; registration failure remains visible and nonfatal. Baseline default-on registration succeeded, Background Task Management reported `[enabled, allowed, notified]`, UI opt-out disabled it, and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history. Current-tree approval-required/retry states and actual login-at-boot after a reboot remain untested.

## Testing policy

- Unit: serialization, migration, validation, conditions, identity matching, CIDR, planning, redaction, error classification, rollback order.
- Presentation unit: saved/draft transitions, save/discard/cancel, external metadata refresh, snapshot-to-draft, included-value summaries, identifier disclosure, menu action reasons, detected choices, and typed condition input validation.
- Mock integration: success, partial force apply, fatal failure and reverse rollback, rollback failure, denied permission, missing device, corrupt storage, import/export.
- Live safe tests: opt-in read-only display, audio, network, input, and readiness-context discovery. Basic login-item registration/status/opt-out/re-enable is manually smoke tested; approval/retry/reboot paths remain pending.
- Live mutation: never in CI and never locally without an explicit environment flag and user action.

All fixtures use synthetic names, documentation-only addresses, and non-personal device identifiers.

UI-hardening commit `5f0cabc` passes full local and [GitHub Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) `make verify` with 214 default non-live tests: 111 XCTest cases with five skipped opt-in live reads and 103 Swift Testing cases with one skipped opt-in Keychain write. The 55 presentation-specific cases comprise 28 draft XCTest cases and 27 presentation/condition Swift Testing cases. Swift and universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, ad-hoc signature classification, and unsigned-package upload pass. The local DMG SHA-256 is `6413e352b3d170b82510b7125f3f8cd0f52b9e5140bfa0977801887d09340e68`; downloaded CI artifact ID `8256718472` verifies CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`.

The five read-only display/audio/network/input/readiness cases passed on the 2026-07-11 baseline when explicitly enabled on an Apple M5 Mac running macOS 26.5.2. Its fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups, and its zero-operation plan kept Apply and Force Apply disabled. They were not rerun for the current UI tree. There is no live mutation, live Keychain-write, physical Intel, current-tree screenshot, full VoiceOver/keyboard, or TCC matrix evidence.

## Static and release verification

Canonical commands are `build`, `test`, `lint`, `analyze`, `package`, `verify-package`, `verify`, and `clean` through the checked-in Makefile. `lint` includes source-policy checks and English/Korean key-parity, duplicate-key, format-placeholder, and static-localization-key validation. `verify` runs format/lint, tests, Swift and universal Xcode Debug/Release builds, Xcode Analyze, DMG creation, checksum validation, mounted-DMG inspection, signature classification, and `git diff --check`. CI performs no live discovery or system mutation. Initial run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue, and repair [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) remains historical compatibility evidence. Current UI-hardening commit `5f0cabc` passed full `make verify` and unsigned-package upload in [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967).

Packaging builds with automatic signing disabled, then ad-hoc signs the staged app. The verifier requires `Signature=adhoc`, no identity authority, and a structurally valid signature. The current local DMG SHA-256 is `6413e352b3d170b82510b7125f3f8cd0f52b9e5140bfa0977801887d09340e68`; downloaded current CI artifact ID `8256718472` verified CI-generated DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. Historical checksums remain in the completion ledger and support matrix. These signatures provide code integrity only: the app has no Developer ID identity, no notarization, and no verified Gatekeeper trust path.
