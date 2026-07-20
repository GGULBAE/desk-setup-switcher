# Product requirements

## Status

Desk Setup Switcher is an unreleased `0.1.0` open-source public-beta candidate. The current 2026-07-21 local release-controls candidate passed integrated non-live `make verify` with 3,938 deterministic checks/assertions: 506 app checks (183 XCTest cases, 322 default Swift Testing cases across 39 suites, and one isolated native popover case in a 40th Swift Testing suite) plus 3,432 release-tooling assertions (351 base release-policy, 659 remote-controls v1 policy/normalizer, 178 remote-controls v2 lifecycle-policy, 69 remote-controls v2 collector, 407 publication-approval policy, 469 external-beta/inventory/lineage policy, 129 collector-wrapper mock, 71 draft-reconciler mock, 246 artifact-restoration mock, 496 approved-publication mock, 152 legacy-workflow-containment mock, and 205 shell/workflow guard assertions). Lint, Swift and universal Xcode Debug/Release, Analyze, project-generation, and mounted package/checksum verification also passed. A separate current-source opt-in read-only run passed all 506 app cases, including Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths, on Apple Silicon/macOS 26.5.2 without setting mutation; it did not itemize actual ColorSync-profile, input-volume, or service-IPv4 field presence/read on that host, and the separate live Keychain-write flag was not enabled. The current development-only DMG SHA-256 is `1934ef766afcc6fd86bbd34efc7e60051e318ba97fe03ffc69b595e7159d45c7`; it is universal and ad-hoc signed without Developer ID and was not installed or launched. The remote-controls, containment, inventory/lineage, external-beta, and publication tooling results are local simulated/structural evidence only. This is not a public release, tester result, candidate-history completeness proof, mutation proof, protected-remote proof, or credentialed signing/notarization result. Signing/notarization, quarantined Gatekeeper, clean lifecycle and external beta evidence—including an exact-candidate Sonoma lifecycle pass—Homebrew own-tap verification, physical Intel, live setting mutation, live Keychain write, and the permission matrix remain unverified. Full-app VoiceOver certification is excluded from the release goal and is not claimed. The separate 496-check result remains a historical baseline in [OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md](OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md); current status is tracked in [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) and [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

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

1. The app launches as an accessory app, shows only a menu-bar item, and leaves its `SMAppService` login item disabled until the user explicitly enables it in Settings.
2. It performs a read-only capability and system snapshot.
3. If there are no profiles, it offers to create one from that snapshot.
4. Permission-dependent values are explained before a prompt and appear as unavailable when permission is declined.

A historical pre-release DMG launched background-only/menu-bar-only, and its then-default-on registration was manually disabled during cleanup. That behavior is superseded: the current baseline resets unproven pre-release registration state to off and preserves only settings recorded after explicit consent. Fresh-off, opt-in, opt-out, consent migration, and approval states are mock verified; no live login-item change or login-at-boot test ran in this pass.

### Create and manage a profile

A user can create, inspect, edit, duplicate, delete, reorder, import, and export profiles. Settings keeps a distinct app-lifetime draft and saved profile: selection, replacement, ordinary quit, and Apply paths require an explicit save/discard/cancel decision when the draft is dirty, and a failed save leaves the draft intact. Successful saves merge user-editable fields into the latest stored metadata. Current settings are captured from the tray as a separate reviewable profile; they never replace an open editor draft.

Display, Audio, and Network groups are flat and always expanded. Every visible leaf has an independent Include switch that preserves its target value when excluded. Common values use typed pickers, toggles, and semantic sliders; runtime catalogs from read-only adapter snapshots are never stored in profile JSON. Audio volume capability follows the input/output device the profile will target. Unsupported runtime choices remain absent, but a persisted included Audio, ColorSync, or service-IPv4 target that later becomes unavailable remains visible as a non-color warning with an Include-off repair control. Field-specific validation blocks invalid saves and connects localized error text to the affected control. Display rotation/active state and administrative IPv4, DNS, and proxy values are retained only as read-only snapshot evidence. An idempotent normalizer excludes these leaves—and any group left without an applicable leaf—when capturing, loading, decoding, planning, or importing without deleting the stored values. Conditions remain round-trip-compatible profile data but are dormant for current manual readiness and Apply. The 2026-07-11 fresh-install smoke test predates this behavior and is not a current UI walkthrough.

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
- **Partial:** at least one included setting is applicable while another is missing, unsupported, blocked, intentionally omitted, or not verified.
- **Unavailable:** no included setting can be applied.
- **Applying:** a transaction is active.
- **Applied:** the last transaction completed with every required result successful and read-back verified, without omission, unsupported work, or failure.
- **Failed:** the last transaction had an apply or rollback failure; a successful rollback does not rewrite the initiating apply failure as success.

State is communicated by text and symbol as well as color. Historical applied/failed outcomes are shown as results; a new readiness refresh is not permanently masked by those older operational states.

## Settings scope

### Displays

Discover connected displays and stable identity attributes; snapshot primary display, topology, mirroring, mode, refresh rate, rotation, and active state where public Core Graphics APIs expose them. The current editor exposes extended/mirrored output, primary display, per-display mode, and portable ColorSync ICC selection; origin, rotation, and active state remain dormant. A typed supported-mode catalog travels only with the current read-only snapshot so the editor can offer a safe picker and preserve a saved mode that is temporarily unavailable; the catalog is not profile data. Validate saved modes before applying. Never persist a `CGDirectDisplayID` as the sole identity. Core Graphics topology starts at app-only scope and **Keep Changes** promotes it to session scope; protected ColorSync work instead retains exact rollback evidence. Timeout, revert, or failed confirmation asks the adapter to restore the prior state. The current-source Display group/base read-only path passed on Apple Silicon/macOS 26.5.2, but the run did not itemize an actual ColorSync-profile presence/read on that host. That item-level claim and all display apply/rollback paths remain mock-only; no mutation was run.

### Audio

Discover Core Audio input/output devices by UID. The current editor and apply payload expose default input, default output, and settable input/output volume. System output and output mute remain round-trip-compatible dormant values rather than `v0.1.0` controls. The read-only capability catalog is device-scoped so a profile that switches devices evaluates the eventual target's volume control. An included change with no writable control is an explicit omission rather than a silent success; an already-matching value remains a no-op. The current-source Audio group/base read-only path passed on Apple Silicon/macOS 26.5.2, but the run did not itemize an actual input-volume field presence/read on that host. That item-level claim and all audio apply/rollback paths remain mock-only; no mutation was run.

### Network

Use CoreWLAN, Network, and SystemConfiguration for current Wi-Fi, Ethernet/link, interface/IP/subnet/gateway/DNS, and readiness facts. The current editor exposes only an exact portable Ethernet/Wi-Fi service target with DHCP or manual IPv4 when one target and exact rollback evidence resolve; apply uses authorized public SystemConfiguration APIs and a protected rollback window. Wi-Fi power/association and legacy global IPv4, DNS, and proxies are not current `v0.1.0` controls; service order is absent rather than persisted. A powered-on interface whose SSID is unreadable is ambiguous, not assumed disassociated, and no Wi-Fi password enters a profile or log. The current-source Network group/base read-only path passed on Apple Silicon/macOS 26.5.2, but the run did not itemize an actual exact service-IPv4 field presence/read on that host. That item-level claim and all network apply/rollback paths remain mock-only; no authorization prompt, service write, or hardware rollback was run.

### Legacy mouse and keyboard compatibility

The versioned profile format and internal experimental adapter boundary can round-trip historical pointer speed, scroll direction, key repeat, repeat delay, and function-key values. They are not edited, applied, advertised, or supported in the `v0.1.0` public surface. Any future visible support requires a separate safe public-API design and evidence pass; undocumented preference keys remain isolated as experimental capability rather than a supported contract.

Vendor application profiles, firmware, proprietary DPI/button mappings, Karabiner rule edits, UI automation, and mutation of another app's files remain out of scope.

## Conditions

The schema can decode and round-trip display, audio input/output, USB/hardware presence, SSID, Ethernet, IP/CIDR, and authorized-location conditions, including all/any and inversion semantics. The current Settings UI does not add or edit them, and current manual readiness/preview/application treats existing or imported conditions as dormant compatibility data so an invisible rule cannot block the user. The pure evaluator and historical choice/input-validation utilities remain regression tested for stored-data compatibility and possible future explicitly designed use. Conditions never initiate an apply operation.

## Accessibility and localization

The menu and settings window provide accessibility names and values, keyboard shortcuts, non-color status cues, actionable error copy, and confirmation for destructive or risky actions. Current source includes distinct names/values for inclusion versus target state, field identifiers and invalid-state descriptions, save/apply/result announcements, text-and-symbol status, an Escape revert and default keep action for display safety, and a remaining-seconds accessibility value. English is the development language and Korean is shipped through localizable resources; lint checks catalog parity, duplicate keys, placeholders, and statically discoverable UI keys.

The 2026-07-14/15 synthetic audit records eight English and eight Korean PNGs plus sixteen read-only AX logs covering overview, current inline deletion/capture feedback, editor/save feedback, 680×480 minimum, simulated large text, validation, System, and diagnostics. User-authorized installed interactions verified deletion Esc/Cancel/Confirm, a resizable Settings window preserving selection/draft/disclosure/focus across 980→680→980, Settings reopen, and the Capture privacy explanation's stable handoff to the app System window. They did not change TCC or prove the full denied/granted matrix. Complete keyboard order, real contrast/text-size/transparency settings, and focused-control behavior remain bounded follow-ups. Full-app VoiceOver certification is neither a release gate nor a product claim; structural metadata does not prove complete assistive-technology behavior.

## Distribution

The deployment target is macOS 14 Sonoma. The planned initial public-beta platform is Apple Silicon, but macOS 14 remains a target rather than a support result until at least one external exact-candidate lifecycle report passes on Sonoma. Development gates cross-build Apple Silicon and Intel slices; physical Intel remains unsupported and unverified. Contributor and CI builds may use the no-Developer-ID DMG with an ad-hoc-signed app, Applications link, versioned filename, and SHA-256 checksum; that artifact is development evidence and is not publishable. Developer ID Application signing, hardened runtime, secure timestamping, notarization, stapling, and Gatekeeper verification are mandatory for the canonical public beta. See [DISTRIBUTION.md](DISTRIBUTION.md).

The current local development-evidence DMG SHA-256 is `1934ef766afcc6fd86bbd34efc7e60051e318ba97fe03ffc69b595e7159d45c7`; its mounted universal `x86_64 arm64` app and ad-hoc/no-Developer-ID status passed verification. It was not installed or launched. Earlier local and installed-interaction checksums remain historical in the completion ledger. Historical UI-hardening artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. Download quarantine/Gatekeeper, a tagged release, publication, and physical Intel remain unverified. The ad-hoc signature supplies integrity, not publisher identity or notarization.

## Non-goals

- Automatic switching or background rules
- Accounts, sync, servers, telemetry, analytics, ads, or paid core features
- Mandatory Homebrew or third-party CLI dependencies at runtime
- App Store distribution as a release prerequisite
- Plaintext Wi-Fi credentials
- Private APIs on the core application path
- Pretending hardware-specific behavior was verified without the relevant hardware
- Full-app VoiceOver certification as a release requirement or marketing claim
