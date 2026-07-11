# Technical specification

## Status and target

This is both the implementation contract and a description of the current pre-release 0.1.0 architecture. A native Swift/SwiftUI menu-bar application, checked-in generated Xcode project, and Swift Package core/system/app targets exist for macOS 14 or later. Core and adapter behavior can be tested without launching the app or changing the host Mac.

The repository targets both `arm64-apple-macos14.0` and `x86_64-apple-macos14.0`. Current universal Debug/Release and packaged builds pass through local `make verify`; no physical Intel Mac has been tested. Scripts use a process-local `DEVELOPER_DIR` fallback when full Xcode is installed but `xcode-select` points to Command Line Tools.

## Module boundaries

```text
DeskSetupSwitcherApp (SwiftUI, menu bar, settings, permissions)
        |
DeskSetupCore (models, validation, conditions, persistence, planning)
        |
DeskSetupSystem (display, audio, network, input, conditions, Keychain)
        |
Public macOS frameworks / explicitly isolated experimental preferences
```

UI code never calls Core Graphics, Core Audio, CoreWLAN, SystemConfiguration, or preference mutation directly. `DeskSetupCore` has no dependency on SwiftUI and tests use mock adapters.

## Concurrency

- UI models and dialogs are `@MainActor`.
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

Capabilities are values, not thrown control flow. Permission denial produces an unavailable item and leaves unrelated groups operational. The app explains location use before its explicit permission action and when a location condition is added; a complete SSID-triggered permission UX matrix is still pending. Listing or selecting a Core Audio input device does not start microphone capture and must not request microphone permission.

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

`MenuBarExtra` hosts the primary UI. `LSUIElement` requests an accessory/menu-bar lifecycle. A Settings scene provides profile management, permissions, login item, sanitized diagnostics, import/export, licenses, and support status. A fresh final-DMG install launched from `/Applications` background-only/menu-bar-only. `SMAppService.mainApp` controls login-at-launch; registration failure remains visible and nonfatal. Default-on registration succeeded, Background Task Management reported `[enabled, allowed, notified]`, UI opt-out disabled it, and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history. Approval-required/retry states and actual login-at-boot after a reboot remain untested.

## Testing policy

- Unit: serialization, migration, validation, conditions, identity matching, CIDR, planning, redaction, error classification, rollback order.
- Mock integration: success, partial force apply, fatal failure and reverse rollback, rollback failure, denied permission, missing device, corrupt storage, import/export.
- Live safe tests: opt-in read-only display, audio, network, input, and readiness-context discovery. Basic login-item registration/status/opt-out/re-enable is manually smoke tested; approval/retry/reboot paths remain pending.
- Live mutation: never in CI and never locally without an explicit environment flag and user action.

All fixtures use synthetic names, addresses, and device identifiers.

Final local `make verify` passes with 158 tests (83 XCTest + 75 Swift Testing); six explicit opt-in cases skip by default. The five read-only display/audio/network/input/readiness cases also pass when enabled on an Apple M5 Mac running macOS 26.5.2. A fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups, and its zero-operation plan kept Apply and Force Apply disabled. There is no live mutation, live Keychain-write, or physical Intel evidence.

## Static and release verification

Canonical commands are `build`, `test`, `lint`, `analyze`, `package`, `verify-package`, `verify`, and `clean` through the checked-in Makefile. `verify` runs format/lint and source-policy checks, tests, Swift and universal Xcode Debug/Release builds, Xcode Analyze, DMG creation, checksum validation, mounted-DMG inspection, signature classification, and `git diff --check`. CI performs no live discovery or system mutation. Initial run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue. Repair commit `4e45328` is pushed, and [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed full `make verify` and unsigned-package upload on 2026-07-11 under macOS 15/Xcode 16.4/Swift 6.1.2.

Packaging builds with automatic signing disabled, then ad-hoc signs the staged app. The verifier requires `Signature=adhoc`, no identity authority, and a structurally valid signature. Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; downloaded CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. The DMGs are not byte-for-byte reproducible. These signatures provide code integrity only: the app has no Developer ID identity, no notarization, and no verified Gatekeeper trust path.
