# System adapter contract

Last updated: 2026-07-18

Desk Setup Switcher's adapters are an internal safety boundary between pure planning and concrete macOS frameworks. The contract is for repository contributors. It is **not** a public SDK, binary compatibility promise, dynamically loadable plug-in API, or invitation for third-party modules to mutate a user's Mac.

`Package.swift` exposes library products so the repository can test its architecture in layers. Their public Swift access control exists for cross-target compilation only; names, signatures, models, and module boundaries may change in a `0.x` release. See [COMPATIBILITY.md](COMPATIBILITY.md).

The source of truth is [`SystemSettingsAdapter`](../Sources/DeskSetupCore/Engine/SystemSettingsAdapter.swift):

```swift
public protocol SystemSettingsAdapter: Sendable {
  var group: SettingGroup { get }

  func capability() async -> AdapterCapability
  func snapshot() async throws -> AdapterSnapshot
  func validate(
    _ desired: SettingsPayload,
    against snapshot: AdapterSnapshot
  ) async -> [ValidationIssue]
  func plan(
    _ desired: SettingsPayload,
    from snapshot: AdapterSnapshot,
    mode: ApplyMode
  ) async throws -> AdapterPlan
  func apply(_ operation: PlannedOperation) async -> OperationResult
  func confirm(_ operation: PlannedOperation) async -> OperationResult
  func rollback(_ operation: PlannedOperation) async -> OperationResult
  func diagnostics() async -> [DiagnosticEntry]
}
```

The product lifecycle branches; it is not one unconditional sequence:

- ordinary success: `prepare(capability → snapshot → validate → plan) → user review → fresh prepare → apply → fresh prepare for read-back verification`;
- protected success: `prepare → user review → fresh prepare → temporary apply → confirm → fresh prepare for read-back verification`;
- fatal apply failure: restore the failing operation when rollback data exists, then roll back completed operations in reverse order; do not issue a confirmation token or run a fresh desired-state verification preparation; and
- failed protected confirmation, Revert, or timeout: consume the pending token and roll back protected operations in reverse order without desired-state verification.

A safely restored nonfatal operation failure may allow later operations to continue. Only successful operations that remain in effect are eligible for the final fresh-prepare verification branch.

There is deliberately no `verify` method on the adapter protocol. On the successful verification branches, product-level verification is a conservative fresh `capability/snapshot/validate/plan` pass. Individual adapters may also perform immediate read-back inside `apply`, `confirm`, or `rollback` when their system API supports it.

## Architecture boundary

| Layer | Owns | Must not own |
| --- | --- | --- |
| [`DeskSetupCore`](../Sources/DeskSetupCore) | Profile/condition models, adapter protocol and typed results, capability/readiness rules, registry, deterministic ordering, transaction and rollback coordination | SwiftUI/AppKit or concrete macOS framework mutations |
| [`DeskSetupSystem`](../Sources/DeskSetupSystem) | Concrete Core Graphics, Core Audio, CoreWLAN, Network, SystemConfiguration, preferences, condition, Keychain, and other macOS adapters behind injected APIs | Product UI, profile-store policy, or direct orchestration decisions |
| [`DeskSetupPresentation`](../Sources/DeskSetupPresentation) | Pure preview/result/read-back classification and presentation state | System framework calls or mutations |
| [`DeskSetupSwitcher`](../Sources/DeskSetupSwitcher) | SwiftUI/AppKit surfaces, explicit review/apply coordination, stale-plan refresh, protected-change countdown, post-apply verification, persistence, and sanitized user messaging | Direct display/audio/network/input framework mutations |

The core owns the protocol so both real adapters and deterministic mocks conform to the same typed contract. The app injects a registry and talks to the core engine; it does not reach around the engine to perform a setting write.

The current concrete setting adapters are:

| Group | Implementation | Boundary |
| --- | --- | --- |
| Display | [`CoreGraphicsDisplayAdapter`](../Sources/DeskSetupSystem/Display/CoreGraphicsDisplayAdapter.swift) | Public Core Graphics and ColorSync-facing system APIs through injected boundaries |
| Audio | [`CoreAudioAdapter`](../Sources/DeskSetupSystem/Audio/CoreAudioAdapter.swift) | Public Core Audio properties through an injected API |
| Network | [`NetworkAdapter`](../Sources/DeskSetupSystem/Network/NetworkAdapter.swift) | CoreWLAN and SystemConfiguration/Network-facing injected APIs |
| Input | [`InputPreferencesAdapter`](../Sources/DeskSetupSystem/Input/InputPreferencesAdapter.swift) | Preferences API with undocumented keys; experimental and dormant in the default product surface |
| Explicit absence | [`UnsupportedSystemSettingsAdapter`](../Sources/DeskSetupSystem/UnsupportedSystemSettingsAdapter.swift) | Typed unsupported capability, omissions, and diagnostics instead of a crash |

Construction of [`LiveAdapterFactory`](../Sources/DeskSetupSystem/Snapshot/LiveAdapterFactory.swift) performs no discovery and changes no setting. Current capability and evidence claims belong in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md), not in an adapter type name.

## Group and registry invariants

`SettingGroup` is one of `display`, `audio`, `network`, or `input`. One process-lifetime [`AdapterRegistry`](../Sources/DeskSetupCore/Engine/AdapterRegistry.swift) accepts at most one adapter per group; duplicate registration is an error.

Every value returned by an adapter must belong to `adapter.group`:

- `AdapterCapability.group`
- `AdapterSnapshot.group` and any non-`nil` snapshot payload
- every `ValidationIssue.group`
- `AdapterPlan.group`
- every planned operation, omission, and plan issue

The snapshot coordinator and apply engine check these boundaries and fail the affected group closed when they disagree. Operation UUIDs must be unique within a plan and across the combined plan; duplicate IDs are removed and surfaced as fatal infrastructure failures.

Persistent target identity must be portable. Runtime device handles, `CGDirectDisplayID`, runtime network service IDs, and BSD interface names are not persistent identity by themselves. Session-only catalogs resolve a portable profile identity against the current host immediately before planning.

## 1. Capability

`capability()` returns `AdapterCapability(group:state:reason:)`. States are:

- `supported`
- `experimental`
- `permissionRequired`
- `temporarilyUnavailable`
- `unsupported`

Only `supported` and `experimental` make `canApply` true. A safe reason must explain the current boundary without exposing identifiers or opaque system errors.

Capability describes whether the adapter may plan/apply the group now; it is not permission to mutate and it is not identical to snapshot readability. The read-only [`SystemSnapshotCoordinator`](../Sources/DeskSetupSystem/Snapshot/SystemSnapshotCoordinator.swift) still asks an adapter for a snapshot so Capture can distinguish readable, permission-required, and unsupported items. The apply engine stops before snapshot/planning when `canApply` is false.

Permission denial is a typed, nonfatal capability for unrelated groups. Adapters must not trigger a system permission prompt merely because capability, readiness, or diagnostics are queried.

## 2. Snapshot

`snapshot()` is read-only. It returns `AdapterSnapshot` with:

- the adapter `group` and `capturedAt` timestamp;
- an optional current `SettingsPayload` for that same group;
- `SnapshotItem` evidence classified as `detected`, `storable`, `unreadable`, `permissionRequired`, or `unsupported`; and
- optional session catalogs needed for editing, matching, preflight, or exact rollback.

The capture coordinator copies a payload into new profile settings only when its group matches and the snapshot contains at least one `storable` item. Detected-only, unreadable, permission-required, and unsupported evidence remains explanatory and must not be invented as a saved mutation target.

The current snapshot model can carry display modes, display color-space evidence, ColorSync profile choices, exact network IPv4 rollback dictionaries, audio devices and writable-volume projections, and saved Wi-Fi names. These values are session context. They must never be copied into `ProfileDocument` unless a separately defined portable profile field exists. Passwords and credential material are prohibited from snapshots, catalogs, operations, logs, and diagnostics.

An empty or partial snapshot must distinguish “successfully observed absence” from “reader unavailable.” Do not convert a read error into an empty collection or a false value that looks authoritative.

## 3. Validate

`validate(_:against:)` compares a same-group desired payload with the supplied snapshot without changing the host. It returns typed `ValidationIssue` values containing `group`, stable `key`, `severity`, `isFatal`, and a safe message.

`severity` is presentation metadata; `isFatal` is the execution boundary. The engine removes operations for fatal keys, and a group-level fatal issue prevents all operations from that group. Normal mode rejects a plan containing fatal issues. Force mode can expose safely available operations from a partial plan, but it does not authorize an adapter to bypass permission, identity ambiguity, missing preflight data, or a required rollback boundary.

Validation must cover the current target, not just JSON shape. Examples include device/service matching, writable properties, supported modes, permission state, saved-network availability, current topology, and the presence of exact rollback evidence. Expected limitations are typed issues or omissions, not thrown crashes.

## 4. Plan

`plan(_:from:mode:)` is also non-mutating. It compares desired state with the same preflight snapshot and returns `AdapterPlan(group:operations:omissions:issues:)`.

Each `PlannedOperation` contains:

- a unique `id`, same-group `key`, and safe `summary`;
- `risk` (`low`, `moderate`, or `high`);
- whether a failure is fatal to the transaction;
- an optional sanitized `OperationPreview(previousValue:desiredValue:)` for local UI only;
- an adapter-private execution `payload`; and
- an adapter-private `rollbackPayload` when the operation can require restoration.

Preview values must not contain passwords, credential data, exact secrets, or opaque error descriptions. Diagnostics intentionally do not serialize previews. Payloads must be deterministic enough for stale-plan comparison and must contain only the minimum data needed by the adapter. For JSON payloads, execution equivalence ignores object-key ordering; other byte payloads compare exactly. Rollback data is part of equivalence, so a changed preflight cannot reuse stale backup state.

An already-satisfied setting produces no operation. An unavailable or intentionally excluded setting produces a typed `PlanOmission`, normally `skipped` or `unsupported`, with a safe reason. A plan must never create an operation merely to make a capability claim look complete.

The engine combines valid plans deterministically: network operations are last, lower-risk operations precede higher-risk operations within that constraint, and stable group/original order breaks ties. Reverse rollback therefore restores network first when a later network operation has already changed connectivity.

## 5. Review and fresh preflight

Preparation is read-only. The app presents the planned changes and explicitly states that nothing has changed. Only the user's Apply action may start execution; readiness, Capture, opening the editor, or satisfying conditions cannot do so automatically.

Immediately before execution, [`ApplicationModel`](../Sources/DeskSetupSwitcher/ApplicationModel.swift) loads the current profile and calls `ApplyEngine.prepare` again. [`ApplyPreparation.isExecutionEquivalent`](../Sources/DeskSetupCore/Engine/ApplyEngine.swift) compares execution-relevant capability, readiness, rejection, validation, operation, preview, execution payload, rollback payload, and omission data while ignoring fresh timestamps and generated presentation IDs.

If either the profile or host-derived plan changed, execution makes zero adapter `apply` calls and returns to a visibly refreshed review. The user must review and apply again. This prevents a preview from becoming standing authorization for a later state.

## 6. Apply and confirm

[`ApplyEngine`](../Sources/DeskSetupCore/Engine/ApplyEngine.swift) serializes transactions. For each operation it looks up the same-group adapter and calls `apply`. `OperationResult.operationID` must match the planned UUID; a mismatch is normalized to failure.

Adapters should report success only after the concrete API reports success and any required immediate read-back agrees. A write request being accepted is not automatically proof that the target state changed. Results use the typed `ApplicationItemStatus` values and safe messages.

Failure handling is conservative:

1. If the failing operation has rollback data, the engine first asks its adapter to restore that operation.
2. A nonfatal failure continues only when the possibly partial operation was positively rolled back.
3. Otherwise the transaction stops, remaining operations are skipped, and every previously completed operation is rolled back in reverse order.
4. Missing, mismatched, or failed rollback leaves a failure result; it is never rewritten as success.

A `high`-risk operation enters protected confirmation after successful apply. The adapter's `apply` must use a temporary/fail-safe system scope when its API provides one. The app keeps the rollback operations pending and presents a 15-second Keep/Revert decision. `confirm` commits the temporary state when needed; the protocol's default implementation is a successful no-op for adapters that committed during `apply`.

Only a transaction that reaches the end without a fatal operation failure may receive a protected-confirmation token. A fatal failure restores the failing operation when possible, rolls back previously completed operations in reverse order, skips the fresh desired-state verification preparation, and returns no token.

Revert, countdown expiry, or confirmation failure consumes the pending token and runs pending high-risk rollbacks in reverse order. These failure/revert branches report rollback outcomes directly and do not run the successful desired-state verification path. A contributor must not mark an operation high risk and rely on the countdown as a substitute for a real, tested temporary scope and rollback payload.

## 7. Verify

Post-apply verification is product orchestration, not a separate adapter method. It runs only for successful operations that remain in effect: after an unprotected execution, including one that safely recovered from a nonfatal item failure, or after protected changes are successfully confirmed. The app calls `ApplyEngine.prepare` again against a fresh read-only snapshot, and [`PostApplyVerificationResult`](../Sources/DeskSetupPresentation/ApplyWorkflowPresentation.swift) then classifies results:

- if the same `group`/`key` is still planned, the write is `notVerified` because the desired change remains required;
- if capability, snapshot, validation, planning, or operation-level read-back is unavailable, the result is `notVerified`, not success;
- an absent remaining operation is `verified` only when the group completed the fresh read/analysis path; and
- operations rolled back during the transaction are excluded from desired-state verification.

Force-mode intentional omissions remain separate from unexpected remaining operations. A successful adapter return plus unavailable fresh read-back produces a partial/not-verified product result.

Adapters may and often should perform narrower immediate read-back inside `apply` or `rollback`; the product-level fresh plan still runs because it checks the final desired state across the transaction.

## 8. Rollback

`rollback(_:)` receives the original `PlannedOperation`, including the exact preflight rollback payload. It must restore the previous state for that operation, return the same operation UUID, and report `rolledBack` only when restoration is positively confirmed to the extent the system API allows.

Rollback is required for any advertised mutation that can leave user-visible or connectivity-affecting state changed. If public APIs cannot capture and restore the previous value safely, the adapter must omit the operation or classify it unsupported/experimental as appropriate. It must not guess a default.

Engine rollback evidence proves only the behavior of the injected adapter in that run. Hardware verification additionally requires an independent fresh snapshot and macOS UI check that the original state was restored. A successful apply without a successful independent restore is failed hardware-mutation evidence.

## 9. Diagnostics

`diagnostics()` is a read-only source of `DiagnosticEntry(timestamp:severity:component:code:message:)`. Entries must be safe to persist locally: no credentials, SSIDs when unnecessary, exact locations, host portions of IP addresses, home paths, device serials, raw payloads, or unredacted framework errors.

The current app persists sanitized orchestration, snapshot, storage, login, and safety events. It does not yet automatically aggregate every concrete adapter's optional `diagnostics()` output into the Settings diagnostics view. Implementing the protocol method is therefore not evidence that its entries are displayed. See [TECHNICAL-SPEC.md](TECHNICAL-SPEC.md) and [PRIVACY.md](PRIVACY.md).

Diagnostics must not initiate discovery that changes permission state, prompt the user, contact an external service, or mutate a setting. Expected capability failures remain usable typed results even when diagnostic storage is unavailable.

## Evidence classifications

Use the repository's evidence vocabulary exactly:

| Classification | What it proves | What it does not prove |
| --- | --- | --- |
| Implemented | A source path exists. | Correct behavior or hardware support. |
| Unit verified | Pure deterministic logic passed without constructing live adapters. | Concrete framework behavior. |
| Mock verified | Injected adapter/API and transaction tests passed without changing the host. | Live read, mutation, or rollback. |
| Live-read verified | An explicitly opted-in capability/snapshot/read test passed on the recorded hardware. | Apply or rollback. |
| Hardware-mutation verified | An approved interactive apply, independent read-back, and independent restoration passed on physical hardware. | Other hardware, OS versions, or untested values. |
| Experimental | The implementation lacks a documented stable OS contract or uses an undocumented preference key behind an explicit capability. | General support. |
| Unsupported/Pending | The app intentionally omits the operation or required evidence is incomplete. | A hidden supported path. |

[`MockSystemSettingsAdapter`](../Sources/DeskSetupCore/Engine/MockSystemSettingsAdapter.swift) is the deterministic core test double. Concrete adapter tests normally inject fake system APIs, which is still mock evidence. The opt-in `DESK_SETUP_LIVE_READ_TESTS=1` tests call only capability, snapshot, and adjacent preparation paths. The ordinary test suite, `make verify`, and CI do not perform live setting mutations.

As recorded on 2026-07-18, no live display, ColorSync, audio, network, or input mutation has hardware-mutation evidence. Do not upgrade that claim based on a green unit test, an adapter's immediate read-back, a read-only snapshot, a universal build, or a successful unsigned package. The current per-feature truth remains in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

## Live-mutation authorization and rollback rules

Live mutation is never an ordinary development, review, or CI step. It may run only when all of these are true:

1. The user gives explicit approval for the named setting group and exact mutation.
2. A dedicated live-mutation opt-in flag gates the procedure; `DESK_SETUP_LIVE_READ_TESTS=1` is not mutation authorization.
3. The user performs an interactive apply action. No UI automation, background trigger, automatic profile switching, or unattended test may substitute for that action.
4. A clean verified commit and artifact are recorded before the test.
5. A read-only preflight profile and an independent, redacted record of the original macOS state exist.
6. A practical manual recovery route is available before applying: for example System Settings, a second usable display/control path, or an alternate network interface.
7. The plan changes one group and the smallest reversible value; unexpected groups, ambiguous identity, missing rollback data, or unsafe permission state cancel the run.
8. The changed state is checked through the relevant macOS UI and a fresh snapshot, then Revert, timeout, workflow red-close, quit, and final “Before” restoration are checked independently.
9. Evidence records the commit, broad redacted hardware class, macOS version, expected/actual behavior, rollback outcome, safe diagnostic IDs, and tester without real SSIDs, exact locations, IP hosts, device UIDs, serials, or credentials.

Use the group-specific procedure in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md). No adapter contribution may weaken these rules or add private APIs, arbitrary shell execution, UI automation, third-party app configuration edits, telemetry, cloud services, or automatic switching.

## Contributor checklist

Before proposing a new or changed adapter behavior:

- keep domain types/protocol changes in `DeskSetupCore`, macOS calls in `DeskSetupSystem`, and UI coordination in the app layer;
- use documented public APIs, or isolate an undocumented preference key behind an experimental capability and update the support matrix;
- define portable identity and keep runtime handles/session catalogs out of profile JSON;
- implement read-only capability/snapshot/validate/plan behavior before any mutation path;
- produce deterministic operations, sanitized previews, exact preflight rollback payloads, no-op behavior, and same-UUID results;
- fail permission denial, hot-plug, target mismatch, read-back disagreement, partial mutation, confirmation failure, and rollback failure conservatively;
- add deterministic success, unsupported, permission, no-op, stale-plan, partial/fatal failure, reverse rollback, and diagnostics-redaction tests;
- keep user-facing strings localizable in English and Korean and preserve keyboard, accessibility-name/value, and non-color cues for any UI change;
- update [README.md](../README.md), [ROADMAP.md](ROADMAP.md), [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md), and [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) when behavior or evidence changes; and
- run `make verify`, `make audit-public-release`, and `git diff --check`, while identifying mock, live-read, and hardware evidence separately.

Core transaction evidence is in [apply-engine tests](../Tests/DeskSetupCoreTests/ApplyEngineTests.swift) and [safety rollback tests](../Tests/DeskSetupCoreTests/SafetyRollbackTests.swift). Concrete adapter tests are under [`Tests/DeskSetupSystemTests`](../Tests/DeskSetupSystemTests), and post-apply classification tests are in [`ApplyWorkflowPresentationTests`](../Tests/DeskSetupPresentationTests/ApplyWorkflowPresentationTests.swift).
