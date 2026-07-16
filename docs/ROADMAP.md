# Roadmap

The roadmap is evidence-based. “Implemented” means source exists; “verified” names the evidence boundary; “done” additionally requires current documentation and the commit or push evidence required by that milestone's explicit contract. Dates are intentionally omitted because safety gates determine sequence.

## M0 — Repository and product contract (done)

- Product, technical, architecture, privacy, support, completion, governance, contribution, security, distribution, and asset-provenance documentation
- Development toolchain baseline

Evidence: committed as `aaea058` (`docs: define production app requirements`) and pushed to `origin/master`.

## M1 — Safe core and runnable shell (pushed and CI verified)

- Deterministically generated checked-in Xcode app project and Swift Package core/system/app targets for macOS 14
- Menu-bar SwiftUI shell, Settings, login-item state/control, English/Korean resources
- Versioned profiles, semantic limits, CRUD/order, atomic permission-restricted storage, backup/quarantine, import/export
- Adapter/capability/readiness contracts, conditions, stable identity, planning, rollback, and diagnostics
- Pre-execution recapture and execution-equivalence checks that return changed operations or rollback payloads to preview

Evidence: initial Actions run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue. Repair commit `4e45328` is pushed, and [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed on 2026-07-11 under macOS 15/Xcode 16.4/Swift 6.1.2 with full `make verify` and unsigned-package upload green.

## M2 — Read-only discovery and profile editing (implemented; mixed hardware verification)

- Display/audio/network/input discovery and isolated snapshot coordinator
- USB/hardware, network, and authorized-recent-location readiness facts
- Profile editing plus condition persistence/evaluation and permission-aware location support; condition editing UI was later retired while stored and imported values remain supported

Evidence: mocks pass. All five opt-in read-only display, audio, network, input, and combined readiness-context tests pass on the current capture-permission source on one Apple M5 Mac. The display gate also verifies that an online session display sleeping with zero active Core Graphics displays is a nonfatal empty fact set, while active states retain count, identity, mode, and snapshot assertions. A historical fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. External display, Ethernet, explicit denied/granted permutations, and physical Intel remain absent.

## M3 — Controlled application (mock verified; no live mutation evidence)

- Audio default/volume/mute, Wi-Fi power/saved association, and experimental input operations
- Network association preflight that requires target saved access and restorable current state; powered-on unreadable SSID is treated as ambiguous
- Core Graphics high-risk apply that starts app-only, promotes to session-only only after confirmation, and restores on timeout/revert/confirmation failure
- Fresh pre-execution plan/rollback validation, fatal reverse rollback, and conservative rollback of a failing operation that may have partially changed state
- Normal/force preview and itemized outcomes

Evidence: injected/mock success and fault tests pass. The fresh snapshot profile had a zero-operation plan and both Apply and Force Apply were disabled. **No live display, audio, network, mouse, or keyboard mutation and no live Keychain write has been run.**

## M4 — UX and release hardening (implemented; full local gate verified)

[UI-REFINEMENT-GOAL.md](UI-REFINEMENT-GOAL.md) records this completed baseline. Its menu, disclosure, and condition decisions are superseded where noted by the active [apply-reliability follow-up](APPLY-RELIABILITY-UX-GOAL.md).

Historical M4 behavior implemented and verified without live flags (later replacements are listed in M4.1):

- App-lifetime saved/draft state with dirty detection, save/discard/cancel replacement protection, external-refresh preservation, authoritative metadata merge, fixed save/revert status, `⌘S`, ordinary-quit protection, and read-only capture into the draft
- Friendly included-value summaries and operation previews with technical details disclosed separately, preserved imported symbols, and deterministic localization at the UI boundary
- Compact top-right Capture plus icon-only Settings/Quit, a typed capture outcome, rejection of unusable snapshots, atomic profile creation/selection, and brief success-only feedback
- One primary Apply action and direct Edit per profile, with ellipsis, availability-review, available-items, and manual-refresh controls absent; disabled-reason text and symbols, bounded scrolling, all-disabled state, and automatic menu-open readiness refresh remain
- Group and option toggles that immediately expand concrete display/audio/network/input value editors, preserve disabled values, and identify unsupported display or administrative-network fields without relying on color
- Condition editing removed while persisted/imported conditions remain preserved, evaluated, and regression tested
- Separate app-desired and macOS login-item state, mismatch-only guidance, About links, text diagnostic severity, accessibility announcements, and display safety keyboard/value metadata
- English/Korean catalog parity, duplicate-key, placeholder, and static-key validation

Evidence: the historical header/editor follow-up passed full local `make verify` with 215 default tests: 112 XCTest with five skips plus 103 Swift Testing cases with one skip. The 56 presentation-specific cases were 29 draft XCTest cases and 27 presentation/condition Swift Testing cases. Universal builds, Analyze, DMG/checksum, mount, resources, architectures, and ad-hoc signature classification passed; local DMG SHA-256 was `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) remain historical remote CI/artifact evidence and predate the apply-reliability follow-up. No live flag, screenshot capture, TCC action, Keychain write, or setting mutation was used.

Historical evidence retained from the 2026-07-11 baseline:

- Fresh `/Applications` launch as a background-only/menu-bar-only app; Korean popover and Settings rendering
- One accessibility-label inspection
- Default-on login-item registration, enabled status, UI opt-out, re-enable, and final disabled cleanup

Remaining optional/manual evidence after the implementation milestone:

- Perform a current-tree non-mutating English/Korean layout and keyboard walkthrough with synthetic data if a safe evidence path is available
- Manually verify approval-required and failure/retry login-item states plus actual login-at-boot after a reboot
- Complete the full English/Korean walkthrough
- Run full VoiceOver, keyboard-only, focus, contrast, text-size, destructive-action, and permission-denial audits
- Manually verify import/export replacement/no-overwrite and diagnostics clearing
- Decide whether diagnostic export belongs in 0.1.0

## M4.1 — Apply reliability and safer editing (locally verified; no push/CI requested)

The active contract is [APPLY-RELIABILITY-UX-GOAL.md](APPLY-RELIABILITY-UX-GOAL.md). The current source and deterministic synthetic tests implement:

- One state-aware primary row action: normal Apply for complete executable plans and Apply Available for partial plans with executable operations, with zero-operation, lock, display-confirmation, refresh, and per-profile preparation reasons
- An idempotent applicability normalizer at capture/decode/store/import/planning boundaries that preserves but excludes display rotation/active state and administrative IPv4/DNS/proxy values, and excludes groups with no applicable leaf
- Dormant, round-trip-compatible legacy conditions that no longer invisibly block current manual readiness, preview, or execution
- Dirty-draft resolution before Apply, followed by the existing fresh-profile/snapshot stale-plan defense
- Value-free complete/partial/failure capture summaries and immediate compact/itemized apply results
- Post-apply read-only replanning that reclassifies a succeeded-but-still-required operation as not verified, plus immediate input-preference read-back
- Inclusion/disclosure separation, typed controls, read-only snapshot-only fields, and field-specific pre-save validation with localized non-color/accessibility metadata

Historical evidence: integrated non-live `make verify` passed on 2026-07-14 with lint/localization policy, 290 default cases (124 XCTest with five opt-in skips plus 166 Swift Testing with one opt-in skip), zero failures, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc signature classification. The verified universal DMG SHA-256 was `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`. No live setting mutation, hardware rollback, TCC action, full VoiceOver run, UI automation, Developer ID signing/notarization, release, push, or new CI run was performed for this follow-up.

## M4.2 — Historical `MenuBarExtra` synthetic UI audit (locally verified; superseded by M4.3)

- DEBUG-only English/Korean audit fixtures cover menu overview, editor, validation, denied-permission presentation, diagnostics, minimum layout, and simulated large text
- The audit model uses a temporary store and injected empty adapters while blocking capture, apply, profile persistence, readiness, login-item, diagnostic, and Core Location request paths
- Settings switches at a fixed 760-point breakpoint between horizontal and vertical `AnyLayout` arrangements; the former draggable split divider is intentionally no longer part of the UX
- Category and option titles receive explicit width priority, while each Include label/switch is a compact fixed-width control, preventing `Form` alignment from vertically compressing Audio rows in Korean
- Profile rows expose one combined accessibility description instead of duplicate name/state elements
- Runtime localization tests load English and Korean bundles deterministically and assert exact formatted output
- Each menu profile now has a directly visible, named Delete control with inline confirmation that remains inside the MenuBarExtra. The viewport follows measured card content up to a scrolling cap rather than estimating from profile count, keeping both confirmation actions visible without retaining an oversized empty tray; Cancel/`Esc` and dirty-draft discard handling remain covered
- Capture now requests Location only after an explicit Capture action and privacy explanation, routes denied access to macOS System Settings or an explicit Wi-Fi-free path, and reports only applicable settings plus actionable permission gaps. Permission actions first request the persistent app System tab, then invoke delayed TCC or macOS System Settings UI so MenuBarExtra focus loss has a visible handoff. Snapshot-only, unreadable, and unsupported evidence no longer creates user-facing partial-capture noise, and the always-unsupported service-order query is absent
- The profile editor replaces dense `Form` alignment with wider cards and a narrower fixed sidebar, while Settings reduces four primary tabs to Profiles/System/About and exposes diagnostics as an on-demand troubleshooting sheet

Evidence: the [manual UI audit](MANUAL-UI-AUDIT-2026-07-14.md) records 16 PNGs and 16 nonempty read-only AX logs. The four current-source additions cover complete bilingual inline deletion/capture feedback and regular/minimum editor feedback layouts. Deterministic tests cover delete state/height, the responsive breakpoint, owned-window resizability/geometry, permission ordering, and synthetic system-access suppression. The [installed deletion/resize log](evidence/manual-ui-audit-2026-07-15/18-installed-delete-resize.txt) proves Esc/Cancel/Confirm, tray persistence, 980→680→980 selected/draft/disclosure/focus preservation, package replacement, and full store rollback. The earlier [permission-handoff log](evidence/manual-ui-audit-2026-07-14/13-installed-permission-handoff.txt) proves the status item, Capture explanation, and stable app System window. macOS resolved Location as already allowed, so the exact permission-result-card action and denied/granted TCC matrix remain pending.

Full keyboard-only traversal, VoiceOver, real macOS text-size, TCC, login approval/retry/reboot, Keychain, Gatekeeper, physical Intel, import/export, and mutation/rollback evidence remains pending.

## M4.3 — Tray Surface Architecture v2 (locally verified; installed interaction pending)

- Production tray ownership is `NSStatusItem` + `.applicationDefined` `NSPopover` + `NSHostingController`; `MenuBarExtra(.window)` and measured SwiftUI height feedback are removed.
- Geometry is computed once per open generation for 0/1/compact/overflow profile states, clamped to the active screen, and held stable while banners, deletion, text size, or async results change. One internal scroll view owns overflow.
- `TrayAction` assigns every control exactly one `stayOpen`, persistent-destination handoff, or terminate disposition. The router coalesces identical in-flight actions, waits for visible/key destinations, leaves failure/cancel reachable, and rejects stale-generation close requests.
- Deletion/focus intent, capture/permission tasks, dirty decisions, previews, safety confirmation, and results are app-lifetime state. Settings and workflow windows are strongly retained and do not depend on popover view lifetime.
- English/Korean strings, icon accessibility labels/help, non-color state text, keyboard shortcuts, and deterministic deletion focus transitions are covered by source/tests.

Evidence: non-live `make verify` passed 326 default cases (130 XCTest + 196 Swift Testing, six opt-in skips), Swift Debug/Release, universal Xcode Debug/Release, Analyze, and mounted DMG verification. SHA-256 is `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`. The [Tray Surface v2 audit](TRAY-SURFACE-AUDIT-2026-07-15.md) records 12 detached-host PNGs and 12 read-only metadata files. It proves contained SwiftUI layout, localization, simulated large text, one high-contrast appearance, and privacy review; the detached host cannot prove actual popover chrome, arrow, anchor, material, ghost-frame absence, native dismissal timing, first responder, or full VoiceOver tree. The v2 package was not installed or launched, and earlier `MenuBarExtra` installed evidence is not reused.

Remaining: user-driven installed status-item/popover interaction, complete keyboard/VoiceOver and real accessibility-setting walkthroughs, TCC, login approval/retry/reboot, Gatekeeper, physical Intel, import/export, Keychain, and every hardware mutation/rollback procedure.

## M5 — Packaging and CI (Tray Surface v2 local package verified; historical CI green)

- The 2026-07-11 post-fix full `make verify` locally passed lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI and tag-triggered release workflows are implemented; CI passed for repair commit `4e45328`
- The historical header/editor follow-up `make verify` produced and verified a universal local DMG with SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`
- UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); unsigned artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`
- The 2026-07-14 apply-reliability `make verify` produced and mounted its then-current universal package with SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`; this is historical package evidence
- The stable permission-handoff follow-up `make verify` produced and mounted its then-current universal package, verified `x86_64 arm64`, resources, checksum, and ad-hoc/no-Developer-ID signature status; SHA-256 is `150d1e0bb620fba52c2ec2a6a78345b5b74f44ca10c9d5375178f6ab16ea370d`. The installed-interaction package SHA-256 `df674b37e2a2fe9a94d37435313265069e27f6130ae05ad02b8ae822ac00e8b6`, pre-stable-handoff capture SHA-256 `ed52b253159e6abc8fe35e606aed56cc269693a53b76986dae20a04ffb2bd4fc`, pre-live-test-adjustment capture SHA-256 `8760d68754f3bc1eebca37319bd0d2bfc29b6b3d90832532e0a64cd072506a9b`, preceding tray/editor SHA-256 `f3d24ae95709d0db9de13ba6032eb63a1d19a5be89af15aa68244da9019afbde`, and layout-correction SHA-256 `ae940ce1cffb969f309b8ffa8f6ffcd0637fd0845ee21bf24fa59129ea530ef7` are historical
- The measured-height tray/responsive-settings follow-up `make verify` produced and mounted historical universal package SHA-256 `8bf4d547fae0df3cbe999db84e7be169b33d495b3993cf7c37f46ba37d6ea71d`; its executable matched the then-installed app byte-for-byte. The pre-correction package SHA-256 `8422b042b793bf0845ac56e2dcbd9808075a0467226d79ee65408440736648d8`, stable permission-handoff, and earlier checksums above are historical.
- Tray Surface v2 supersedes that package. Its non-live gate produced and mounted universal SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`; installation, launch, push, and CI were not performed.

Remaining:

- Perform a quarantined Gatekeeper/Open Anyway install on a clean user account or Mac
- Complete remaining non-mutating manual workflows, accessibility audit, and login approval/retry/reboot cases
- Publish a tag only after green CI and a current evidence ledger

## M4.4 — Tray reopen and profile-detail refinement (historical; superseded by M4.5)

- Reset zero-origin AppKit viewport geometry for every tray generation; after `NSPopover.show`, attach one generation-scoped top-scroll request directly to the first content block so the first open cannot miss it and no anchor-only stack row adds blank spacing. A deterministic 20-cycle regression preserves the fixed viewport and one-scroll architecture.
- Keep Settings/Profile Edit and other workflow destinations app-lifetime persistent, frontmost-before-tray-close, exactly-once, and recoverable after repeated red-close cycles. While at least one destination is visible, the process and windows participate in the ordinary macOS app/window cycle; the final explicit close restores tray-only accessory policy.
- Remove the profile editor's current-settings draft refresh button and helper copy. Tray Capture remains the explicit current-state entry point and creates a new reviewable profile.
- Replace Quit's power glyph with localized `xmark` semantics and derive a variable-length status-item symbol/name only from fresh enabled-profile matching or applying state.
- Reduce the profile surface to alias/symbol/enabled plus Display, Audio, and Network while preserving and excluding hidden legacy data.
- Add public Core Audio input-volume snapshot/apply/rollback coverage and portable Ethernet/Wi-Fi service IPv4 identity/read capability. Color-mode and IPv4 writes remain explicitly disabled where public rollback-safe support is unavailable.
- Record synthetic Display/Audio/Network evidence and the [refinement audit](TRAY-SETTINGS-REFINEMENT-AUDIT-2026-07-15.md). No installed app, live mutation, TCC change, Keychain write, push, or publication is part of this milestone.
- Integrated non-live `make verify` passes 339 cases (132 XCTest + 207 Swift Testing, six opt-in skips), all build/Analyze stages, and universal mounted-DMG verification. Current local SHA-256 is `567917f169e90799db177d0a5f22a8b13115cb30ed63f7e766fc4bb992ab35e3`.

## M4.5 — Tray/settings end-to-end contract (implemented locally)

- Make first attachment deterministic: 368-point width, 260/300/316/560-point height tiers for 0/1/2/3+ profiles, symmetric 16-point root padding, generation-guarded post-show attachment, one first-layout completion, and one final viewport synchronization without sleeps.
- Remove profile activation as a product concept. Legacy false values normalize to active applicability and no longer hide a row or block apply.
- Remove group/option disclosure and every disabled/read-only/future placeholder from the default editor. Keep the visible surface flat, always expanded, and limited to complete Display/Audio/Network vertical slices.
- Establish `VisibleSettingRegistry` as the nine-kind capture→edit→validate→plan→apply→verify→rollback invariant, with typed runtime catalogs and unsupported/ambiguous controls absent.
- Add portable public ColorSync ICC profile selection with ID + ICC SHA-256 persistence, current-catalog resolution, exact read-back, and prior-mapping rollback after display topology.
- Complete default input/output and settable input/output-volume Core Audio slices, with device switching before device-scoped volume and unsupported controls omitted.
- Add authorized per-service DHCP/manual IPv4 apply with exact serialized rollback data, public SystemConfiguration lock/commit/apply/unlock orchestration, dynamic-store completion, exact read-back, network-last apply, and network-first protected rollback.
- Generalize the 15-second safety window to protected display/network operations; window close, timeout, Revert, confirmation failure, and termination restore temporary state.
- Record deterministic vertical-slice, rollback-order, first-attach, twenty-reopen, dynamic completion/timeout, localization, and synthetic evidence. The [end-to-end audit](TRAY-SETTINGS-END-TO-END-AUDIT-2026-07-16.md) distinguishes mock/offscreen proof from installed/native/hardware gaps.
- Integrated non-live `make verify` passes 366 cases (134 XCTest + 232 Swift Testing, five opt-in skips), all build/Analyze stages, and universal mounted-DMG verification. Current local SHA-256 is `76bc6d9f1187ea30f68be16ee81ee4a334d877a4e26c2497f35a9ffc781678b3`.

No live display/audio/network mutation, install, push, tag, signing/notarization, or publication is part of M4.5.

## M4.6 — installed empty-state and apply-handoff follow-up

- Ignore the actual `NSPopover` container's asymmetric horizontal safe area at the SwiftUI root and keep one symmetric 16-point content inset. Replace the tall native unavailable-content view with a compact explicit empty state.
- Rename the tray's state-aware action to Review/Review Available, explain that the preview has not changed settings, and keep Apply Profile as the only mutation confirmation.
- Return a changed execution preflight to a visibly marked refreshed review without invoking adapters; expose rejected confirmation guards instead of silently returning.
- Add an asymmetric-safe-area raster regression, stable/changed execution-preflight adapter tests, and an opt-in adjacent read-only live-preparation check.
- Integrated non-live `make verify` passes 370 default cases (134 XCTest with five skips + 236 Swift Testing with two disabled opt-in cases), all build/Analyze stages, and universal mounted-DMG verification. SHA-256 is `e2927513543903b794bea08628064b29c12604e18706bef169c20b3e89760bcd`.
- The verified package replaced `/Applications/Desk Setup Switcher.app` and passed identity, version, `x86_64 arm64`, and signature checks. It was not launched after replacement, and no live setting mutation ran.

Evidence: [installed empty/apply follow-up](INSTALLED-EMPTY-APPLY-FOLLOWUP-2026-07-16.md).

## Current next task — reinstalled smoke check, then hardware audit

Launch the reinstalled app and first run user-driven checks for the empty tray alignment, repeated opens, Review→Apply Profile wording, and visible result/error states. Continue with application/Space switching, red-close recovery, native English/Korean rendering, keyboard focus, and VoiceOver. Only after a separate explicit mutation approval and preflight snapshot, execute the support-matrix ColorSync/Core Audio/Ethernet/Wi‑Fi IPv4 procedures and independently verify rollback. Import/export, the full permission matrix, login approval/retry/reboot, Gatekeeper, and physical Intel remain separately authorized work.

Release publication, push, Gatekeeper, physical Intel, full VoiceOver/TCC testing, signing/notarization, and any live mutation-and-rollback procedure remain separate and require their own authorization boundaries in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).
