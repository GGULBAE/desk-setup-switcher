# Product requirements

## Status

Desk Setup Switcher is a pre-release 0.1.0 implementation candidate. Post-fix full local `make verify` passes with 158 tests (83 XCTest + 75 Swift Testing), as do the five opt-in read-only hardware gates, universal no-Developer-ID DMG/checksum verification, and a fresh `/Applications` smoke test. Repair commit `4e45328` is pushed, and [Actions run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed full `make verify` and unsigned-package upload under macOS 15/Xcode 16.4/Swift 6.1.2. This is not a public release or mutation proof: no live setting mutation, physical Intel run, live Keychain write, or quarantined Gatekeeper test exists. See [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) and [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

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

The fresh final-DMG install launched background-only/menu-bar-only. Default-on `SMAppService` registration succeeded; UI opt-out disabled it and re-enable restored enabled status, followed by a final opted-out cleanup. Approval-required and failure/retry states plus actual login-at-boot after a reboot remain unverified.

### Create and manage a profile

A user can create, inspect, edit, duplicate, delete, reorder, enable, import, and export profiles. A snapshot pre-fills only values that were actually read. Each group and individual option can be included or excluded. A profile includes a name, description, SF Symbol, conditions, and last-application summary; the containing document carries the schema version. The fresh-install smoke test created one schema-v1 Ready profile from a read-only snapshot with all four groups.

### Apply a profile

The app evaluates conditions and adapter capabilities, calculates a change plan, and skips no-op values.

- Normal apply is available only when every enabled setting can be applied.
- Force apply requires explicit confirmation, lists omissions first, and applies only supported/available values.
- Force confirmation is disabled if no change is possible.
- Before execution, the app recaptures profile/condition/system state and refreshes the plan. If execution-relevant operations or rollback payloads changed, it requires another preview instead of using stale state.
- Results are recorded per setting as succeeded, failed, skipped, unsupported, rolled back, or rollback failed.
- A fatal failure rolls completed steps back in reverse order when rollback is supported.
- Risky display changes are initially app-only, become session-scoped only after confirmation, and restore the prior arrangement on timeout/revert or confirmation failure.

The fresh snapshot profile produced a zero-operation plan, so both Apply and Force Apply were disabled and no live setting changed.

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

Discover connected displays and stable identity attributes; snapshot primary display, topology, mirroring, mode, refresh rate, rotation, and active state where public Core Graphics APIs expose them. Validate saved modes before applying. Never persist a `CGDirectDisplayID` as the sole identity. High-risk changes require preflight backup and an app-only temporary commit; **Keep Changes** promotes the same configuration to session scope, while timeout/revert/failed confirmation restores the backup. This path is mock verified, not live-mutation verified.

### Audio

Discover Core Audio input/output devices by UID; snapshot and apply default input, default output, system output, volume, and mute when supported. A device without software volume or mute reports unsupported for that property instead of causing profile failure.

### Network

Use CoreWLAN, Network, and SystemConfiguration for Wi-Fi power and current network facts, Ethernet/link facts, interface/IP/subnet/gateway/DNS snapshots, and readiness conditions. Saved-network association may use credentials already held by macOS; secrets are never placed in profiles or logs. The app plans a switch only after preflighting the target saved access and a safe rollback target. A powered-on interface whose SSID is unreadable is ambiguous, not assumed disassociated. Administrative network mutations remain out of scope until a public, rollback-safe implementation is evidenced.

### Mouse and keyboard

Support macOS-wide pointer speed, scroll direction, key repeat, repeat delay, and function-key preference when a safe interface is available. Undocumented preference keys are isolated as experimental capability, not misrepresented as a supported public API.

Vendor application profiles, firmware, proprietary DPI/button mappings, Karabiner rule edits, UI automation, and mutation of another app's files are out of scope.

## Conditions

Conditions include display, audio input/output, USB/hardware presence, SSID, Ethernet, IP/CIDR, and location when authorized. A condition set supports all/any matching and inversion. Conditions never initiate an apply operation.

## Accessibility and localization

The menu and settings window support VoiceOver labels, keyboard navigation, sufficient contrast, non-color status cues, macOS text/accessibility preferences, actionable error copy, and confirmation for destructive or risky actions. English is the development language and Korean is shipped through localizable resources.

The fresh-install popover and Settings rendered in Korean, and an accessibility label passed inspection. A complete English/Korean walkthrough and full VoiceOver/keyboard/focus/contrast/text-size audit remain release work; this section is the acceptance target, not a completed claim.

## Distribution

The minimum deployment target is macOS 14 Sonoma. Release builds target both Apple Silicon and Intel. The project produces a no-Developer-ID DMG with an ad-hoc-signed app, Applications link, versioned filename, and SHA-256 checksum. Developer ID signing and notarization are optional. See [DISTRIBUTION.md](DISTRIBUTION.md).

The post-fix local DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; downloaded CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. The DMGs are not byte-for-byte reproducible. Download quarantine/Gatekeeper, a tagged release, publication, and physical Intel remain unverified. The ad-hoc signature supplies integrity, not publisher identity or notarization.

## Non-goals

- Automatic switching or background rules
- Accounts, sync, servers, telemetry, analytics, ads, or paid core features
- Mandatory Homebrew or third-party CLI dependencies at runtime
- App Store distribution as a release prerequisite
- Plaintext Wi-Fi credentials
- Private APIs on the core application path
- Pretending hardware-specific behavior was verified without the relevant hardware
