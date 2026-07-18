# Security policy

## Supported versions

There is no public release yet. The table describes the current pre-release boundary; it does not turn a local or CI artifact into a supported download.

| Version | Security status |
| --- | --- |
| Default development branch | Reports are accepted and fixes land here before the first public beta. Development snapshots are not supported end-user releases. |
| `v0.1.0` public beta | Not published yet. It becomes supported only after the signed, notarized release is published through GitHub Releases. |
| Older builds and untagged artifacts | Unsupported. Do not redistribute the current ad-hoc-signed test DMG as a release. |

During the `0.x` public-beta period, the latest published beta receives security fixes. The immediately preceding beta may receive critical fixes for up to 30 days when a safe backport is practical. After a stable release exists, the latest and immediately preceding stable minor lines are the intended support window. See [Compatibility and versioning](docs/COMPATIBILITY.md) for the application, platform, schema, and Swift-package policies.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability, exposed secret, unsafe system mutation, profile-import exploit, privacy leak, or rollback failure.

**Current repository state (checked 2026-07-18): GitHub private vulnerability reporting is disabled.** Until a repository administrator enables it, contact [the repository owner](https://github.com/GGULBAE) and request a private reporting channel. Do not include vulnerability details, exploit material, secrets, or unredacted diagnostics in that initial public contact. The issue tracker and support form are public and must not be used for security reports.

Before the first public beta is announced, a repository administrator must enable GitHub private vulnerability reporting, replace the repository's **Security reporting instructions** contact link with the private advisory URL, and verify that it opens a private form. Once enabled, this document should be updated to make `https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new` the primary reporting path.

Include affected commit/version, macOS version, impact, reproduction steps using synthetic data, and whether any live setting was changed. Remove credentials, serial numbers, SSIDs, exact locations, IP host portions, home paths, and diagnostics that have not been redacted.

We aim to acknowledge a complete report within 7 days and provide a status update within 14 days. These are targets, not an uptime SLA, bug-bounty program, embargo agreement, or compensation commitment.

## Security boundaries

- Profile imports are untrusted and must be size-limited, decoded without side effects, migrated explicitly, and semantically validated.
- Credentials belong in Keychain and must never be serialized or logged.
- The app must not execute arbitrary shell commands, use UI automation, call private APIs, or modify another app's settings files.
- Diagnostics remain local, rotate, and pass through redaction.
- The app has no telemetry or application-owned outbound network communication.
- Mutating adapters require validation, typed operations, backup, itemized results, and rollback semantics.

General feature requests and non-sensitive bugs belong in the issue tracker.
