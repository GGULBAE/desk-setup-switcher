# Security policy

## Supported versions

There is no public release yet. Security fixes currently target the default development branch. A version support table will be added with the first release.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability, exposed secret, unsafe system mutation, profile-import exploit, privacy leak, or rollback failure. Use GitHub's private vulnerability reporting feature for this repository if it is enabled. If it is not available, contact the repository owner through their GitHub profile and request a private reporting channel without including exploit details in the initial public message.

Include affected commit/version, macOS version, impact, reproduction steps using synthetic data, and whether any live setting was changed. Remove credentials, serial numbers, SSIDs, exact locations, IP host portions, home paths, and diagnostics that have not been redacted.

We aim to acknowledge a complete report within 7 days and provide a status update within 14 days. These are goals, not a bug-bounty or compensation commitment.

## Security boundaries

- Profile imports are untrusted and must be size-limited, decoded without side effects, migrated explicitly, and semantically validated.
- Credentials belong in Keychain and must never be serialized or logged.
- The app must not execute arbitrary shell commands, use UI automation, call private APIs, or modify another app's settings files.
- Diagnostics remain local, rotate, and pass through redaction.
- The app has no telemetry or application-owned outbound network communication.
- Mutating adapters require validation, typed operations, backup, itemized results, and rollback semantics.

General feature requests and non-sensitive bugs belong in the issue tracker.
