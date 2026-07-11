# Technical specification

## Status and target

This is the implementation contract for a pre-alpha repository. The initial target is a native Swift/SwiftUI menu-bar application for macOS 14 or later, built with the checked-in Xcode project. Core domain logic is also exposed through a Swift package so it can be tested without launching the app or changing the host Mac.

The repository must build against both `arm64-apple-macos14.0` and `x86_64-apple-macos14.0`. Scripts use a process-local `DEVELOPER_DIR` fallback when full Xcode is installed but `xcode-select` points to Command Line Tools.

## Module boundaries

```text
DeskSetupSwitcherApp (SwiftUI, menu bar, settings, permissions)
        |
DeskSetupCore (models, validation, conditions, persistence, planning)
        |
SystemAdapters (display, audio, network, input, login item)
        |
Public macOS frameworks / explicitly isolated experimental preferences
```

UI code never calls Core Graphics, Core Audio, CoreWLAN, SystemConfiguration, or preference mutation directly. `DeskSetupCore` has no dependency on SwiftUI and tests use mock adapters.

## Concurrency

- UI models and dialogs are `@MainActor`.
- Profile persistence and transaction coordination are actors.
- Only one apply transaction may run at a time.
- Adapters must honor cancellation between individual planned operations.
- Result ordering is deterministic even when read-only capability probes run concurrently.

## Versioned profile format

The top-level document contains:

- `schemaVersion`
- `profiles`
- `selectedProfileID`
- `updatedAt`

Every profile uses UUID identity and contains metadata, ordered enabled setting groups, per-option inclusion flags, typed setting payloads, typed conditions, and an optional last application summary. Dates use `Date`'s stable ISO-8601 encoding strategy at file boundaries. Unknown future fields are ignored; unknown required enum values fail validation with a user-facing error.

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
2. Write to a sibling temporary file.
3. Flush and atomically replace the primary file.
4. Retain the last known-good backup.
5. On decoding failure, copy the bad file to a timestamped `Quarantine` directory, restore the valid backup when possible, and otherwise start with an empty document while surfacing diagnostics.

Export uses a user-selected destination. Import reads only the selected file and passes the same size, schema, and semantic validation. Secrets use Keychain; profiles and backups never contain passwords.

## Adapter contract

Every setting adapter exposes the same conceptual operations:

- `capability(context)`: supported, experimental, permission-required, temporarily unavailable, or unsupported, with reason
- `snapshot(context)`: read-only state plus detected/unreadable/permission-required/unsupported items
- `validate(desired, snapshot, context)`: typed issues and fatality
- `plan(desired, snapshot, mode)`: ordered no-op-filtered operations and rollback metadata
- `apply(operation, context)`: per-item result
- `rollback(operation, backup, context)`: per-item rollback result
- `diagnostics(context)`: redacted, locally persisted support information

Adapters are injected by group identifier. Domain tests never construct live adapters.

## Apply transaction

```text
snapshot -> evaluate conditions/capabilities -> validate -> plan
         -> capture backup -> apply low-risk operations in order
         -> success OR fatal error -> reverse rollback -> result
```

Normal mode rejects a plan with any enabled unavailable item. Force mode records unavailable items as skipped and proceeds only after explicit UI confirmation. A plan with zero applicable operations is disabled. No-op comparisons are adapter-specific and must tolerate insignificant numeric variance.

Each planned operation declares risk and dependency. Default order is input preferences, audio, network, then display; adapter-specific dependencies can refine the order. Display topology/mode operations are committed as one Core Graphics configuration where possible.

A failure is fatal only when continuing could create an inconsistent or unsafe configuration. Rollback failure is recorded separately and never replaces the original error.

## Capability and permission behavior

Capabilities are values, not thrown control flow. Permission denial produces an unavailable item and leaves unrelated groups operational. Location authorization is explained and requested only when SSID/location-dependent features are selected. Listing or selecting a Core Audio input device does not start microphone capture and must not request microphone permission.

## Stable device identity

- Display: UUID when available plus vendor/model/serial, built-in flag, and a conservative fallback fingerprint; runtime display IDs are session-only.
- Audio: Core Audio device UID; names are presentation only.
- Network: interface BSD name plus interface type; SSIDs are condition values, not credentials.
- USB/hardware: stable registry attributes available through public IOKit APIs, with capability reasons when identity is ambiguous.

Ambiguous matching never silently chooses a device. It produces a validation issue that the user can resolve.

## Logging and diagnostics

Structured local log entries contain timestamp, severity, component, safe event code, and a redacted summary. The redactor removes secrets, exact location, SSIDs where diagnostics do not need them, IP host portions, filesystem home paths, and Keychain material. Logs rotate by size and count. There is no remote logger and no application-owned outbound network request.

## App lifecycle

`MenuBarExtra` hosts the primary UI. `LSUIElement` keeps the Dock icon hidden. A Settings scene provides profile management, permissions, login item, diagnostics, import/export, licenses, and support status. `SMAppService.mainApp` controls login-at-launch; registration failure is visible and does not prevent use.

## Testing policy

- Unit: serialization, migration, validation, conditions, identity matching, CIDR, planning, redaction, error classification, rollback order.
- Mock integration: success, partial force apply, fatal failure and reverse rollback, rollback failure, denied permission, missing device, corrupt storage, import/export.
- Live safe tests: opt-in read-only discovery and login status.
- Live mutation: never in CI and never locally without an explicit environment flag and user action.

All fixtures use synthetic names, addresses, and device identifiers.

## Static and release verification

Canonical commands are `build`, `test`, `lint`, `analyze`, `package`, `verify`, and `clean` through the checked-in task runner. `verify` runs formatting/lint checks, tests, Debug and Release builds, architecture checks, and `git diff --check`; packaging adds DMG structure and SHA-256 verification. CI performs no live system mutation.
