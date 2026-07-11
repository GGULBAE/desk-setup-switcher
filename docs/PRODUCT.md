# Product requirements

## Status

Desk Setup Switcher is in pre-alpha development. This document defines the product that the repository is intended to ship; it does not describe already verified behavior. See [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) for the evidence ledger.

## Product promise

Desk Setup Switcher is a free, open-source, local-first macOS menu-bar app that lets a person capture the current desk-related settings as a profile and deliberately apply a saved profile later. It never changes profiles automatically.

The app covers displays, audio, network state, and the macOS-wide mouse and keyboard settings that can be accessed safely. A profile's conditions answer “can this profile be applied here?” They are readiness checks, not triggers.

## Product principles

- Manual control: no location-, network-, schedule-, or device-triggered application.
- Preview first: show the proposed changes, omissions, and risks before mutation.
- Safe degradation: unavailable devices, denied permissions, and unsupported features do not crash or disable unrelated capabilities.
- Local only: no accounts, cloud service, telemetry, analytics, or outbound application traffic.
- Least privilege: request a permission only when the user selects a feature that needs it.
- Public API first: experimental implementations are isolated and clearly labelled.
- Honest capability reporting: “unsupported” is a valid result, never a silent failure.
- Reversible changes: take a preflight snapshot and roll back completed steps after a fatal failure when the adapter can safely do so.

## Primary journeys

### First launch

1. The app launches as an accessory app, shows only a menu-bar item, and attempts to enable its `SMAppService` login item.
2. It performs a read-only capability and system snapshot.
3. If there are no profiles, it offers to create one from that snapshot.
4. Permission-dependent values are explained before a prompt and appear as unavailable when permission is declined.

### Create and manage a profile

A user can create, inspect, edit, duplicate, delete, reorder, enable, import, and export profiles. A snapshot pre-fills only values that were actually read. Each group and individual option can be included or excluded. A profile includes a name, description, SF Symbol, conditions, schema version, and last-application summary.

### Apply a profile

The app evaluates conditions and adapter capabilities, calculates a change plan, and skips no-op values.

- Normal apply is available only when every enabled setting can be applied.
- Force apply requires explicit confirmation, lists omissions first, and applies only supported/available values.
- Force apply is disabled if no change is possible.
- Results are recorded per setting as succeeded, failed, skipped, unsupported, or rolled back.
- A fatal failure rolls completed steps back in reverse order when rollback is supported.
- Risky display changes use a timed confirmation flow and restore the prior arrangement when not confirmed.

## Readiness states

- **Ready:** all enabled settings and required conditions are satisfiable.
- **Partial:** at least one enabled setting is applicable and at least one is missing, unsupported, or blocked.
- **Unavailable:** no enabled setting can be applied.
- **Applying:** a transaction is active.
- **Applied:** the last transaction completed without a failed enabled item.
- **Failed:** the last transaction had a failure; its rollback outcome remains visible.

State is communicated by text and symbol as well as color.

## Settings scope

### Displays

Discover connected displays and stable identity attributes; snapshot primary display, topology, mirroring, mode, refresh rate, rotation, and active state where public Core Graphics APIs expose them. Validate saved modes before applying. Never persist a `CGDirectDisplayID` as the sole identity. High-risk changes require preflight backup, rollback, and timed confirmation.

### Audio

Discover Core Audio input/output devices by UID; snapshot and apply default input, default output, system output, volume, and mute when supported. A device without software volume or mute reports unsupported for that property instead of causing profile failure.

### Network

Use CoreWLAN, Network, and SystemConfiguration for Wi-Fi power and current network facts, Ethernet/link facts, interface/IP/subnet/gateway/DNS snapshots, and readiness conditions. Saved-network association may use credentials already held by macOS; secrets are never placed in profiles or logs. Administrative network mutations remain out of the core path until a public, rollback-safe implementation is evidenced.

### Mouse and keyboard

Support macOS-wide pointer speed, scroll direction, key repeat, repeat delay, and function-key preference when a safe interface is available. Undocumented preference keys are isolated as experimental capability, not misrepresented as a supported public API.

Vendor application profiles, firmware, proprietary DPI/button mappings, Karabiner rule edits, UI automation, and mutation of another app's files are out of scope.

## Conditions

Conditions include display, audio input/output, USB/hardware presence, SSID, Ethernet, IP/CIDR, and location when authorized. A condition set supports all/any matching and inversion. Conditions never initiate an apply operation.

## Accessibility and localization

The menu and settings window support VoiceOver labels, keyboard navigation, sufficient contrast, non-color status cues, macOS text/accessibility preferences, actionable error copy, and confirmation for destructive or risky actions. English is the development language and Korean is shipped through localizable resources.

## Distribution

The minimum deployment target is macOS 14 Sonoma. Release builds target both Apple Silicon and Intel. The project produces an unsigned DMG with the app, an Applications alias, a versioned filename, and a SHA-256 checksum. Developer ID signing and notarization are optional. See [DISTRIBUTION.md](DISTRIBUTION.md).

## Non-goals

- Automatic switching or background rules
- Accounts, sync, servers, telemetry, analytics, ads, or paid core features
- Mandatory Homebrew or third-party CLI dependencies at runtime
- App Store distribution as a release prerequisite
- Plaintext Wi-Fi credentials
- Private APIs on the core application path
- Pretending hardware-specific behavior was verified without the relevant hardware
