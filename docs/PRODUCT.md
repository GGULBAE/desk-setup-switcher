# Product requirements

## Status

Desk Setup Switcher is a pre-release 0.1.0 implementation candidate. The current canonical apply-plan follow-up on Tray Surface Architecture v2 passed integrated non-live `make verify` on 2026-07-16 with 371 default cases (134 XCTest plus 237 Swift Testing), zero failures, lint, Swift and universal Xcode Debug/Release, Analyze, and mounted package/checksum verification. The current DMG SHA-256 is `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`; it is universal and ad-hoc signed without Developer ID and replaced the `/Applications` bundle, but it was not launched afterward. This is not a public release or mutation proof: actual corrected click-through, live setting mutation, physical Intel, live Keychain write, full VoiceOver/TCC audit, and quarantined Gatekeeper remain unverified. See [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) and [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

## Product promise

Desk Setup Switcher is a free, open-source, local-first macOS menu-bar app that lets a person capture the current desk-related settings as a profile and deliberately apply a saved profile later. It never changes profiles automatically.

The current visible surface covers displays, audio, and service-specific network state. Legacy mouse/keyboard settings and imported conditions remain in the versioned format for round-trip compatibility, but the current manual workflow neither edits nor applies them and never lets conditions silently block readiness or Apply. Conditions never act as triggers.

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

A user can create, inspect, edit, duplicate, delete, reorder, enable, import, and export profiles. Settings keeps a distinct app-lifetime draft and saved profile: selection, replacement, ordinary quit, and Apply paths require an explicit save/discard/cancel decision when the draft is dirty, and a failed save leaves the draft intact. Successful saves merge user-editable fields into the latest stored metadata. A current-settings snapshot pre-fills only values that were actually read and changes the reviewable draft, not the persistent profile, until the user saves.

Setting inclusion and disclosure are independent: collapsing an included group or option does not exclude it or erase its target value. Common values use typed pickers, toggles, and semantic sliders; the display-mode picker consumes a typed runtime catalog from the read-only adapter snapshot and never stores that catalog in profile JSON. Field-specific validation blocks invalid saves and connects localized error text to the affected control. Display rotation/active state and administrative IPv4, DNS, and proxy values are retained only as read-only snapshot evidence. An idempotent normalizer excludes these leaves—and any group left without an applicable leaf—when capturing, loading, decoding, planning, or importing without deleting the stored values. Conditions remain round-trip-compatible profile data but are dormant for current manual readiness and Apply. The 2026-07-11 fresh-install smoke test predates this behavior and is not a current UI walkthrough.

### Apply a profile

The app evaluates current adapter capabilities, calculates a change plan, and skips no-op values. Legacy conditions are not a hidden gate in this manual path.

The top-right header exposes short Capture plus icon-only Settings and Quit actions. Each profile has one state-aware primary action in a stable location: `Review…` for a complete normal plan, or `Review Available…` for a partial plan with executable items. Both open an explicit preview and do not mutate settings; only the separate `Apply Profile` confirmation starts execution. Edit remains direct, and readiness refreshes automatically without discarding a usable cached action. Per-profile preparation prevents duplicate taps. A dirty draft is resolved before planning, then the latest stored profile and read-only system state are prepared again so an older saved value cannot be applied silently. If that execution preflight changes, nothing is applied and the refreshed review is shown again.

Capture treats the user's Capture action as the permission-request boundary for the current Wi-Fi name. An undetermined Location state first explains the purpose, then requests macOS authorization only after the user continues; denied or restricted states offer macOS System Settings or an explicit Wi-Fi-free capture. Before TCC or macOS System Settings takes focus, the app opens its persistent permission workflow and the tray router waits until that destination is visible and key before closing. Presentation failure or cancellation keeps the tray reachable. The result remains value-free, saves applicable leaves, and shows only actionable permission gaps. Snapshot-only, unreadable, unsupported, and runtime-identifier evidence is omitted from the user-facing error card, while a capture with no applicable leaf still does not create a profile. Disabled Apply actions use a text-and-symbol reason. Profile summaries and previews lead with friendly included values; opaque identifiers remain behind explicit technical disclosures.

- Normal apply is available only when every included applicable setting can be applied.
- Available-items/force apply requires explicit confirmation, lists omissions separately, and applies only supported/available values.
- Force confirmation is disabled if no change is possible.
- Before execution, the app recaptures profile/condition/system state and refreshes the plan. If execution-relevant operations or rollback payloads changed, it requires another preview instead of using stale state.
- Results are recorded per setting as succeeded, failed, skipped, unsupported, rolled back, rollback failed, or not verified.
- After a non-display-safety execution, a new read-only preparation checks whether an executed operation is still required and whether the relevant capability/snapshot can be read safely. A still-needed operation or unavailable read-back is reported as not verified rather than finalized as applied; intentional force omissions stay distinct. High-risk display results are finalized after Keep/Revert.
- A fatal failure rolls completed steps back in reverse order when rollback is supported.
- Risky display changes are initially app-only, become session-scoped only after confirmation, and restore the prior arrangement on timeout/revert or confirmation failure.

The historical fresh snapshot profile produced a zero-operation plan, so both Apply and Force Apply were disabled and no live setting changed. No current follow-up path has been exercised against live hardware.

## Readiness states

- **Ready:** all included, applicable settings can be prepared and the plan has no blocking omission.
- **Partial:** at least one enabled setting is applicable while another is missing, unsupported, blocked, intentionally omitted, or not verified.
- **Unavailable:** no enabled setting can be applied.
- **Applying:** a transaction is active.
- **Applied:** the last transaction completed with every required result successful and read-back verified, without omission, unsupported work, or failure.
- **Failed:** the last transaction had an apply or rollback failure; a successful rollback does not rewrite the initiating apply failure as success.

State is communicated by text and symbol as well as color. Historical applied/failed outcomes are shown as results; a new readiness refresh is not permanently masked by those older operational states.

## Settings scope

### Displays

Discover connected displays and stable identity attributes; snapshot primary display, topology, mirroring, mode, refresh rate, rotation, and active state where public Core Graphics APIs expose them. A typed supported-mode catalog travels only with the current read-only snapshot so the editor can offer a safe picker and preserve a saved mode that is temporarily unavailable; the catalog is not profile data. Validate saved modes before applying. Never persist a `CGDirectDisplayID` as the sole identity. High-risk changes require preflight backup and an app-only temporary commit; **Keep Changes** promotes the same configuration to session scope, while timeout/revert/failed confirmation restores the backup. This path is mock verified, not live-mutation verified.

### Audio

Discover Core Audio input/output devices by UID; snapshot and apply default input, default output, system output, volume, and mute when supported. A device without software volume or mute reports unsupported for that property instead of causing profile failure.

### Network

Use CoreWLAN, Network, and SystemConfiguration for Wi-Fi power and current network facts, Ethernet/link facts, interface/IP/subnet/gateway/DNS snapshots, and readiness conditions. Saved-network association may use credentials already held by macOS; secrets are never placed in profiles or logs. The app plans a switch only after preflighting the target saved access and a safe rollback target. A powered-on interface whose SSID is unreadable is ambiguous, not assumed disassociated. Administrative network mutations remain out of scope until a public, rollback-safe implementation is evidenced.

### Mouse and keyboard

Support macOS-wide pointer speed, scroll direction, key repeat, repeat delay, and function-key preference when a safe interface is available. Undocumented preference keys are isolated as experimental capability, not misrepresented as a supported public API.

Vendor application profiles, firmware, proprietary DPI/button mappings, Karabiner rule edits, UI automation, and mutation of another app's files are out of scope.

## Conditions

The schema can decode and round-trip display, audio input/output, USB/hardware presence, SSID, Ethernet, IP/CIDR, and authorized-location conditions, including all/any and inversion semantics. The current Settings UI does not add or edit them, and current manual readiness/preview/application treats existing or imported conditions as dormant compatibility data so an invisible rule cannot block the user. The pure evaluator and historical choice/input-validation utilities remain regression tested for stored-data compatibility and possible future explicitly designed use. Conditions never initiate an apply operation.

## Accessibility and localization

The menu and settings window provide VoiceOver labels, keyboard shortcuts, non-color status cues, actionable error copy, and confirmation for destructive or risky actions. Current source includes distinct labels/values for inclusion versus target state, field identifiers and invalid-state descriptions, save/apply/result announcements, text-and-symbol status, an Escape revert and default keep action for display safety, and a remaining-seconds accessibility value. English is the development language and Korean is shipped through localizable resources; lint checks catalog parity, duplicate keys, placeholders, and statically discoverable UI keys.

The 2026-07-14/15 synthetic audit records eight English and eight Korean PNGs plus sixteen read-only AX logs covering overview, current inline deletion/capture feedback, editor/save feedback, 680×480 minimum, simulated large text, validation, System, and diagnostics. User-authorized installed interactions verified deletion Esc/Cancel/Confirm, a resizable Settings window preserving selection/draft/disclosure/focus across 980→680→980, Settings reopen, and the Capture privacy explanation's stable handoff to the app System window. They did not change TCC or prove the full denied/granted matrix. No full VoiceOver/keyboard-order/contrast/real-text-size audit has run. Structural localization and deterministic accessibility metadata checks do not prove translation quality or complete assistive-technology behavior; this section remains the acceptance target, not a completed claim.

## Distribution

The minimum deployment target is macOS 14 Sonoma. Release builds target both Apple Silicon and Intel. The project produces a no-Developer-ID DMG with an ad-hoc-signed app, Applications link, versioned filename, and SHA-256 checksum. Developer ID signing and notarization are optional. See [DISTRIBUTION.md](DISTRIBUTION.md).

The current local DMG SHA-256 is `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`; its mounted universal `x86_64 arm64` app and ad-hoc/no-Developer-ID status passed verification. It replaced the `/Applications` bundle but was not launched afterward. Earlier local and installed-interaction checksums remain historical in the completion ledger. Historical UI-hardening artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. Download quarantine/Gatekeeper, a tagged release, publication, and physical Intel remain unverified. The ad-hoc signature supplies integrity, not publisher identity or notarization.

## Non-goals

- Automatic switching or background rules
- Accounts, sync, servers, telemetry, analytics, ads, or paid core features
- Mandatory Homebrew or third-party CLI dependencies at runtime
- App Store distribution as a release prerequisite
- Plaintext Wi-Fi credentials
- Private APIs on the core application path
- Pretending hardware-specific behavior was verified without the relevant hardware
