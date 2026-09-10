# Product requirements

## Status

Desk Setup Switcher is preparing an unreleased `0.1.0`/build-2 open-source public beta. The current repository source is intentionally `0.0.9`/build 1 so the protected predecessor can be built, retained, tagged, and externally upgraded before the final candidate is introduced. On 2026-07-22, non-live `make verify` passed 5,298 deterministic checks/assertions: 516 app checks (192 XCTest, 323 default Swift Testing cases across 39 suites, and one isolated native popover case in a 40th Swift Testing suite) plus 4,782 release-tooling assertions (374 base release-policy, 8 Mach-O compatibility-verifier, 659 remote-controls v1 policy/normalizer, 210 remote-controls v2 lifecycle-policy, 86 remote-controls v3 lifecycle-policy, 71 remote-controls v2 collector, 17 remote-controls v3 collector, 407 publication-approval policy, 1,386 external-beta/inventory/lineage/template policy, 132 collector-wrapper mock, 19 release-evidence history, 57 draft-reconciler mock, 261 artifact-restoration mock, 557 approved-publication mock, 306 legacy-workflow-containment mock, and 232 shell/workflow guard assertions). The local release contract uses three remote-controls v3 phases and four exact workflow identities, retains both protected attempt-1 origins, creates a draft only for the final candidate, and binds external-beta report v3/set v2 plus predecessor-lineage v3 to the mandatory `0.0.9` → `0.1.0` upgrade and requires exact manifest-matched `/Applications` installs for both origins before launch. The remote-controls, containment, inventory/lineage, external-beta, and publication results remain local simulated/structural evidence only: no workflow was pushed, no remote control changed, and no tag, signing credential, tester result, site, or Release was created. The current development DMG was not installed, launched, uploaded, or published. A separate 2026-07-20 opt-in read-only run passed all 506 then-current app cases on Apple Silicon/macOS 26.5.2 without setting mutation; it did not prove the item-level hardware fields, Sonoma runtime, live Keychain write, or any apply/rollback path. Signing/notarization, quarantined Gatekeeper, exact-candidate clean lifecycle and three external beta reports, Homebrew own-tap verification, physical Intel, live setting mutation, and the permission matrix remain unverified. Full-app VoiceOver certification is excluded from the release goal and is not claimed. Current verification and package evidence are tracked in [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) and [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).

## Product promise

Desk Setup Switcher is a free, open-source, local-first macOS menu-bar app that lets a person capture the current desk-related settings as a profile and deliberately apply a saved profile later. It never changes profiles automatically.

The visible surface is limited to six display/sound settings: main display, resolution, output device/volume, input device/volume. Other historical settings and imported conditions remain format-compatible dormant data, never automatic triggers or hidden profile changes.

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

The editor presents stable numbered **Display** and **Sound** steps. Minimum/accessibility layouts retain the compact segmented selector. All six setting kinds appear directly, without Advanced or Network. Validation selects the owning step before moving focus; unavailable saved volume has an inclusion-off repair row. Runtime catalogs are never stored in profile JSON. Normalization excludes every retired leaf at capture/load/import/plan boundaries without deleting old values, including in Force mode. Last-application history is not shown. The current scope and non-live evidence are recorded in [the minimal-profile note](MINIMAL-PROFILE-SCOPE-2026-09-07.md).

### App preferences

**App Settings** contains launch-at-login preferences and an on-demand Diagnostics action. It refreshes the effective macOS registration state when opened; mismatch status, refresh, and retry actions appear directly beside the launch preference only when needed. These preferences apply to the app, independently of the selected profile.

### Apply a profile

The app evaluates current adapter capabilities, calculates a change plan, and skips no-op values. Legacy conditions are not a hidden gate in this manual path.

The top-right header exposes short Capture plus icon-only Settings and Quit actions. Each profile has one state-aware primary action in a stable location: `Review Changes…` for a complete normal plan, or `Review Available Changes…` for a partial plan with executable items. Both open an explicit preview and do not mutate settings; only the separate `Apply Profile` confirmation starts execution. Exactly three standard profile cards use a 480-point tray while four or more retain the 560-point overflow viewport. At constrained width the complete readiness label moves below the title instead of truncating, and destructive deletion lives in the secondary profile menu. Edit remains direct, and readiness refreshes automatically without discarding a usable cached action. Per-profile preparation prevents duplicate taps. Apply Preview exposes change/skip/review counts and current → target cards first, while ordinary omissions, validation, and rejections stay in one disclosure that opens automatically for a blocked plan. A dirty draft is resolved before planning with separate unsaved-profile and target-profile rows, then the latest stored profile and read-only system state are prepared again so an older saved value cannot be applied silently. If that execution preflight changes, nothing is applied and the refreshed review is shown again.

Capture reads only Display/Audio and proceeds regardless of Location permission. A dirty draft still requires Save/Discard/Cancel before creating a separate captured profile. Results remain value-free and report applicable captured fields; an empty applicable capture creates no profile. Disabled Apply actions retain text/symbol reasons. Profile summaries and previews use friendly values, with opaque identifiers behind explicit technical disclosures.

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

Discover display identity and capture only primary display and resolution. The editor exposes those two choices directly. Resolution does not save or apply a refresh-rate preference: choose a supported resolution at the current rate or skip the unsupported combination. Mirroring, color, origins, rotation, and active state are not current profile options. Complete live topology is read only for transaction validation and rollback. Primary changes translate origins as required by macOS without requesting a new relative arrangement. Core Graphics changes stay app-only until Keep promotes them to session scope; timeout/Revert/failure restores prior state. These mutation paths remain mock-only.

### Audio

Discover Core Audio input/output devices by UID. Capture, editor, and Apply expose exactly default output, output volume, default input, and input volume, with independent inclusion switches and runtime device-scoped writable-volume checks. System output and mute are no longer captured; legacy values remain dormant. Unavailable volume changes produce explicit omissions or an inclusion-off repair control, and matching values are no-ops. No microphone recording permission is requested. Apply/rollback remains mock-only.

### Network

No Network option is part of the current product profile. Default Capture does not instantiate Network/Input adapters or gate on Location permission. All imported network values, including service-specific DHCP/manual IPv4, are preserved with inclusion disabled before planning, even in Force. Historical CoreWLAN/SystemConfiguration and condition primitives remain internal compatibility/mock coverage, not current profile capabilities.

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

The current `v0.0.9`/build-1 local development-evidence DMG is `artifacts/Desk-Setup-Switcher-0.0.9-unsigned.dmg`, SHA-256 `2a743a6df6c14ad4b2ae3b1fc4ecc5bdeb7527089165d3ed7e6db32c1d5cf0c4`; its mounted app passed exact `arm64+x86_64`, per-slice macOS 14.0 `LC_BUILD_VERSION`, and ad-hoc/no-Developer-ID verification. It remains local development evidence and was not uploaded or published. Earlier local and installed-interaction checksums remain historical in the completion ledger. Historical UI-hardening artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`. The DMGs are not byte-for-byte reproducible. Download quarantine/Gatekeeper, a tagged release, publication, and physical Intel remain unverified. The ad-hoc signature supplies integrity, not publisher identity or notarization.

## Non-goals

- Automatic switching or background rules
- Accounts, sync, servers, telemetry, analytics, ads, or paid core features
- Mandatory Homebrew or third-party CLI dependencies at runtime
- App Store distribution as a release prerequisite
- Plaintext Wi-Fi credentials
- Private APIs on the core application path
- Pretending hardware-specific behavior was verified without the relevant hardware
- Full-app VoiceOver certification as a release requirement or marketing claim
