# Compatibility and versioning

Last updated: 2026-07-18

This document fixes the public compatibility boundary for the planned Desk Setup Switcher `v0.1.0` public beta. It distinguishes the app, its local profile format, and Swift Package targets; they do not share the same compatibility promise.

## Release identity

| Item | `v0.1.0` baseline | Policy |
| --- | --- | --- |
| Release tag | `v0.1.0` | Tags use `v` plus SemVer. A published tag or artifact is never replaced; a correction uses a new patch version. |
| App version | `CFBundleShortVersionString = 0.1.0` | Must exactly match the release tag without `v`. |
| Build number | `CFBundleVersion = 1` | Must be a positive integer and increase for every distributed candidate built from the same app version. |
| Bundle identifier | `dev.ggulae.desk-setup-switcher` | Stable application identity. Changing it requires an explicit install, local-data, login-item, and Keychain migration plan. |
| Keychain service namespace | `dev.ggulae.desk-setup-switcher.secrets` | Stable secret-store boundary. It is not a profile field and must not be changed without a credential migration and rollback plan. |
| Deployment target | macOS 14.0 or later | Raising it is a user-visible compatibility change and must be stated in release notes. |

Before `1.0`, minor versions may change behavior and internal source interfaces. Patch versions must remain focused on compatible fixes, security remediation, and release repair. Release notes must call out profile-format, permission, supported-platform, and behavior changes even when SemVer permits them.

## CPU support

The Xcode and package gates currently cross-build a universal `arm64 x86_64` executable, and package inspection confirms both slices. Runtime and install evidence exists on Apple Silicon. Physical Intel execution, clean install, upgrade, profile recovery, and mutation/rollback have not been verified.

Therefore the initial public beta support claim is **Apple Silicon only**. The `x86_64` slice is an unverified convenience artifact, not an Intel support claim. Intel support may be added only after the physical verification matrix is recorded in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

## Swift Package products

`Package.swift` exposes `DeskSetupCore`, `DeskSetupPresentation`, and `DeskSetupSystem` library products so the app can keep architecture boundaries testable. They are **internal, unstable implementation products**, not a supported SDK or plugin API.

- Public Swift access control is used where targets must communicate; it does not create a source- or binary-compatibility commitment for external consumers.
- Names, signatures, models, protocols, and module boundaries may change in any `0.x` release without a deprecation period.
- The repository does not publish a library compatibility matrix or promise Swift Package API stability.
- Third-party integrations should not depend on these products. A future supported SDK would require a separate proposal, versioned documentation, conformance tests, and an explicit stability policy.

The adapter sequence `snapshot → validate → plan → apply → verify → rollback` is the internal safety contract for contributors. It describes architecture, not a dynamically loadable extension point.

## Profile JSON schema

The current profile document schema is `schemaVersion: 1`.

- A document with an explicit integer JSON `schemaVersion: 0` is migrated deterministically to schema 1 before semantic validation.
- Schema 1 is decoded and semantically/resource validated before it may replace local state.
- Missing versions, booleans, floating or fractional number representations, negative versions, malformed versions, and versions newer than the running app understands are rejected rather than guessed or silently downgraded.
- The profile schema contains no password field. Exports can still contain sensitive labels, SSIDs, network ranges, device identifiers, and exact location conditions and must be reviewed before sharing.

For the `0.1.x` line, schema 1 is the readable/writable interchange format. Before a future release raises the schema version, it must add deterministic migration from every profile schema written by a still-supported public release, preserve a last-known-good backup, and add failure-path tests. Older apps may reject a document written by a newer schema; forward compatibility is not promised.

The JSON format is intended for app import/export and recovery. It is not a stable third-party automation API. Hand-edited or generated documents remain untrusted input and are accepted only when the running app's decoder and validators approve them.

## Supported release lines

- Before the first public beta: only the default branch receives fixes; no end-user artifact is supported.
- During public beta: the latest published beta is supported. The immediately preceding beta may receive critical security fixes for up to 30 days when a safe backport is practical.
- After stable releases begin: the latest and immediately preceding stable minor lines are the intended support window. Older lines receive no fixes unless a maintainer announces an exception.

Publication and support status must agree across [SECURITY.md](../SECURITY.md), [SUPPORT.md](../SUPPORT.md), [DISTRIBUTION.md](DISTRIBUTION.md), the support matrix, release notes, and the canonical GitHub Release.
