# Roadmap

The roadmap is evidence-based. “Implemented” means source exists; “verified” names the evidence boundary; “done” additionally requires current documentation and the commit or push evidence required by that milestone's explicit contract. Dates are intentionally omitted because safety gates determine sequence.

## M0 — Repository and product contract (done)

- Product, technical, architecture, privacy, support, completion, governance, contribution, security, distribution, and asset-provenance documentation
- Development toolchain baseline

Evidence: committed as `aaea058` (`docs: define production app requirements`) and pushed to `origin/master`.

## M1 — Safe core and runnable shell (pushed and CI verified)

- Deterministically generated checked-in Xcode app project and Swift Package core/system/app targets with a macOS 14.0 deployment target
- Menu-bar SwiftUI shell, Settings, login-item state/control, English/Korean resources
- Versioned profiles, semantic limits, CRUD/order, atomic permission-restricted storage, backup/quarantine, import/export
- Adapter/capability/readiness contracts, conditions, stable identity, planning, rollback, and diagnostics
- Pre-execution recapture and execution-equivalence checks that return changed operations or rollback payloads to preview

Evidence: initial Actions run `29154880831` for `0d8f510` exposed the Swift 6.1 actor-isolation issue. Repair commit `4e45328` is pushed, and [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed on 2026-07-11 under macOS 15/Xcode 16.4/Swift 6.1.2 with full `make verify` and unsigned-package upload green.

## M2 — Read-only discovery and profile editing (implemented; mixed hardware verification)

- Display/audio/network/input discovery and isolated snapshot coordinator
- USB/hardware, network, and authorized-recent-location readiness facts
- Profile editing plus condition persistence/evaluation and permission-aware location support; condition editing UI was later retired while stored and imported values remain supported

Evidence: mocks pass. On 2026-07-20, `DESK_SETUP_LIVE_READ_TESTS=1 make test` passed all 506 then-current app cases on one Apple M5 Mac running macOS 26.5.2. Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths ran read-only. The display gate verified that an online session display sleeping with zero active Core Graphics displays is a nonfatal empty fact set, while active states retained count, identity, mode, and snapshot assertions. The dated run did not itemize actual ColorSync-profile, input-volume, or exact service-IPv4 field presence/read on that host; those item-level claims and every apply/rollback path remain mock-only. A historical fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. External display, Ethernet, explicit denied/granted permutations, Sonoma runtime, live mutation, and physical Intel remain absent.

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
- Run keyboard-only, focused-control AX, contrast, text-size, destructive-action, and permission-denial audits. Full VoiceOver certification is excluded and unclaimed
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

Evidence: the [manual UI audit](MANUAL-UI-AUDIT-2026-07-14.md) records 16 PNGs and 16 nonempty read-only AX logs. The four recorded additions cover complete bilingual inline deletion/capture feedback and regular/minimum editor feedback layouts. Deterministic tests cover delete state/height, the responsive breakpoint, owned-window resizability/geometry, permission ordering, and synthetic system-access suppression. The [installed deletion/resize log](evidence/manual-ui-audit-2026-07-15/18-installed-delete-resize.txt) proves Esc/Cancel/Confirm, tray persistence, 980→680→980 selected/draft/disclosure/focus preservation, package replacement, and full store rollback. The earlier [permission-handoff log](evidence/manual-ui-audit-2026-07-14/13-installed-permission-handoff.txt) proves the status item, Capture explanation, and stable app System window. macOS resolved Location as already allowed, so the exact permission-result-card action and denied/granted TCC matrix remain pending.

Full keyboard-only traversal, focused-control AX observation, real macOS text-size, TCC, login approval/retry/reboot, Keychain, Gatekeeper, physical Intel, import/export, and mutation/rollback evidence remain pending. VoiceOver was unrun at that milestone; full VoiceOver certification is now excluded and unclaimed rather than tracked as pending work.

## M4.3 — Tray Surface Architecture v2 (locally verified; installed interaction pending)

- Production tray ownership is `NSStatusItem` + `.applicationDefined` `NSPopover` + `NSHostingController`; `MenuBarExtra(.window)` and measured SwiftUI height feedback are removed.
- Geometry is computed once per open generation for 0/1/compact/overflow profile states, clamped to the active screen, and held stable while banners, deletion, text size, or async results change. One internal scroll view owns overflow.
- `TrayAction` assigns every control exactly one `stayOpen`, persistent-destination handoff, or terminate disposition. The router coalesces identical in-flight actions, waits for visible/key destinations, leaves failure/cancel reachable, and rejects stale-generation close requests.
- Deletion/focus intent, capture/permission tasks, dirty decisions, previews, safety confirmation, and results are app-lifetime state. Settings and workflow windows are strongly retained and do not depend on popover view lifetime.
- English/Korean strings, icon accessibility labels/help, non-color state text, keyboard shortcuts, and deterministic deletion focus transitions are covered by source/tests.

Evidence: non-live `make verify` passed 326 default cases (130 XCTest + 196 Swift Testing, six opt-in skips), Swift Debug/Release, universal Xcode Debug/Release, Analyze, and mounted DMG verification. SHA-256 is `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`. The [Tray Surface v2 audit](TRAY-SURFACE-AUDIT-2026-07-15.md) records 12 detached-host PNGs and 12 read-only metadata files. It proves contained SwiftUI layout, localization, simulated large text, one high-contrast appearance, and privacy review; the detached host cannot prove actual popover chrome, arrow, anchor, material, ghost-frame absence, native dismissal timing, first responder, or full VoiceOver tree. The v2 package was not installed or launched, and earlier `MenuBarExtra` installed evidence is not reused.

Remaining at that milestone: user-driven installed status-item/popover interaction, complete keyboard/focused-control AX and real accessibility-setting walkthroughs, TCC, login approval/retry/reboot, Gatekeeper, physical Intel, import/export, Keychain, and every hardware mutation/rollback procedure. Full VoiceOver certification is now excluded and unclaimed.

## M5 — Packaging and CI (P2 local package verified; historical CI green)

- The 2026-07-11 post-fix full `make verify` locally passed lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI passed for repair commit `4e45328`. The effective remote tag workflow remains an unsafe historical unsigned-publication path; the safer local signed-candidate draft/prerelease proposal is unpushed and neither path has produced public-beta distribution evidence
- The historical header/editor follow-up `make verify` produced and verified a universal local DMG with SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`
- UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); unsigned artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`
- The 2026-07-14 apply-reliability `make verify` produced and mounted its then-current universal package with SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`; this is historical package evidence
- The stable permission-handoff follow-up `make verify` produced and mounted its then-current universal package, verified `x86_64 arm64`, resources, checksum, and ad-hoc/no-Developer-ID signature status; SHA-256 is `150d1e0bb620fba52c2ec2a6a78345b5b74f44ca10c9d5375178f6ab16ea370d`. The installed-interaction package SHA-256 `df674b37e2a2fe9a94d37435313265069e27f6130ae05ad02b8ae822ac00e8b6`, pre-stable-handoff capture SHA-256 `ed52b253159e6abc8fe35e606aed56cc269693a53b76986dae20a04ffb2bd4fc`, pre-live-test-adjustment capture SHA-256 `8760d68754f3bc1eebca37319bd0d2bfc29b6b3d90832532e0a64cd072506a9b`, preceding tray/editor SHA-256 `f3d24ae95709d0db9de13ba6032eb63a1d19a5be89af15aa68244da9019afbde`, and layout-correction SHA-256 `ae940ce1cffb969f309b8ffa8f6ffcd0637fd0845ee21bf24fa59129ea530ef7` are historical
- The measured-height tray/responsive-settings follow-up `make verify` produced and mounted historical universal package SHA-256 `8bf4d547fae0df3cbe999db84e7be169b33d495b3993cf7c37f46ba37d6ea71d`; its executable matched the then-installed app byte-for-byte. The pre-correction package SHA-256 `8422b042b793bf0845ac56e2dcbd9808075a0467226d79ee65408440736648d8`, stable permission-handoff, and earlier checksums above are historical.
- Tray Surface v2 supersedes that package. Its non-live gate produced and mounted universal SHA-256 `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`; installation, launch, push, and CI were not performed.
- The 2026-07-17 native UI structural follow-up's integrated gate passed 446 checks (144 XCTest + 301 Swift Testing across 38 suites + one separately executed native `NSPopover` regression) and produced a mounted universal package with SHA-256 `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`. That package was reinstalled to `/Applications` for the separately authorized non-mutating UI geometry follow-up; it is now preceding evidence.
- The P2 UI refinement final local gate passed 461 checks: 144 XCTest, 316 Swift Testing across 39 suites, and one isolated native popover regression. Its universal no-Developer-ID DMG SHA-256 is `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`; the reinstalled ad-hoc-signed `/Applications` executable SHA-256 is `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719`. The app launched on Apple Silicon, the installed executable contained `x86_64 arm64`, the x86_64 slice was not run, and profile primary/backup/defaults remained unchanged. Preceding hashes must not be reused. Push and CI were not requested by the local P2 goal.

Remaining:

- Perform an exact downloaded/quarantined Gatekeeper install on a clean user account or Mac; an official candidate must open without **Open Anyway**
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

- Make first attachment deterministic: 368-point width, 260/260/316/560-point height tiers for 0/1/2/3+ profiles, symmetric 16-point root padding, generation-guarded post-show attachment, one first-layout completion, and one final viewport synchronization without sleeps.
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

## M4.7 — canonical execution-plan comparison

- Reproduce the repeated refreshed-review loop with the explicitly gated read-only selected-profile preparation check. Adjacent plans had equal visible values but different Core Audio JSON byte ordering.
- Encode new Core Audio operation and rollback commands with sorted keys and canonicalize JSON object ordering in the core execution-equivalence comparison.
- Preserve fail-closed behavior for changed JSON values, changed rollback evidence, and non-JSON operation bytes.
- Prevent the opt-in live regression from rendering preparation operands on failure; its diagnostic comment contains only modes, groups, counts, and equality booleans.
- Integrated non-live `make verify` passes 371 default cases (134 XCTest with five skips + 237 Swift Testing with two disabled opt-in cases), all build/Analyze stages, and universal mounted-DMG verification. SHA-256 is `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`.
- A separate read-only adjacent preparation passed normal and available-items modes in 0.148 seconds. The verified package replaced `/Applications/Desk Setup Switcher.app` without automatic launch or setting mutation.

## M4.8 — tray, Settings, and workflow UI stability follow-up

- Freeze the variable-width status-item anchor for each open popover generation: cached readiness remains usable during refresh, duplicate presentations are ignored, and the latest title/width is applied after close.
- Keep empty idle tray content outside scrolling, make Capture icon-only with explicit accessibility copy, keep the header on one line, give every open generation a new top-anchored scroll identity, and remove animated focus scrolling.
- Use one horizontal Settings workspace from the 680-point minimum upward instead of flipping the whole sidebar/editor anatomy at 760 points. Keep footer and save/revert action bars at stable heights.
- Keep the runtime editor catalog stable while refresh is in flight, adopt at most the first completed read-only refresh in each presentation, suppress identical editor publications, replace lazy editor layout with deterministic layout, make invalid-save validation feedback reachable, and reset scroll only on profile identity or a hidden-window reopen.
- Reset every refreshed apply preview to its top explanatory notice, keep notices and changes in one scroll region above a fixed footer, make workflow child screens fill one persistent canvas, bound protected-change summaries with internal scrolling, and use monospaced countdown digits.
- Record the [UI stability audit](UI-STABILITY-AUDIT-2026-07-16.md), including the three installed references, before/after synthetic evidence, default and minimum-large-text preview evidence, accessibility limits, and manual 20-open/resize/profile-switch checks.
- Integrated non-live `make verify` passes 375 default cases (134 XCTest with five skips + 241 Swift Testing with two disabled opt-in cases), all build/Analyze stages, and universal mounted-DMG verification. SHA-256 is `516b968718aeb3c1c247e1a2deca7a28d45820d119f31ea992d4b475071f3638`; the verified package replaced `/Applications/Desk Setup Switcher.app` without launch or setting mutation.

No live display/audio/network mutation, UI automation, TCC action, Keychain write, push, tag, notarization, or publication is part of M4.8.

## M4.9 — settings lifecycle and UI declutter refactor

- Remove routine and duplicated copy from Settings, login status, previews, and result counts while retaining every error, omission, not-verified, rollback, permission, progress, and accessibility state.
- Delete the unused app-layer condition editor and obsolete private helpers while keeping condition schema/import/storage/evaluator compatibility in Core.
- Prove editor load/edit/save/fresh-reload/apply/read-back as one deterministic injected lifecycle with no live adapter.
- Reject zero-operation plans in every mode and collapse semantically duplicate adapter issues before presentation.
- Make Audio capability target-device scoped and turn changed-but-unavailable Audio, ColorSync, and service-IPv4 values into explicit omissions. Preserve already-satisfied values as omission-free no-ops and keep color-only planning independent from unused topology rollback.
- Keep previously included unavailable targets repairable with a warning and Include-off control without exposing never-included unsupported controls.
- Stage profile bytes and private permissions before atomic replacement; cover pre-commit failure and backup recovery ordering with temporary-directory tests.
- Record the source/test/evidence boundary in [SETTINGS-LIFECYCLE-REFACTOR-2026-07-16.md](SETTINGS-LIFECYCLE-REFACTOR-2026-07-16.md).
- Integrated non-live `make verify` passes 401 default cases (144 XCTest with five opt-in skips + 257 Swift Testing with two default-disabled opt-in cases), all build/Analyze stages, and universal mounted-DMG verification. SHA-256 is `f3aa610026179161208dec2cb2ef6185768843becd8e0e56bccc9f8abab37f2b`; the package was not installed or launched.

No installed-app launch, live hardware mutation, TCC action, Keychain write, UI automation, push, tag, notarization, or publication is part of M4.9.

## M4.10 — native UI structural reliability follow-up

- Replace duplicate/dynamic horizontal safe-area ignores with one public AppKit parent boundary that preserves the native popover's top/bottom chrome exclusion while filtering left/right to zero before SwiftUI's first attached proposal.
- Preserve AppKit ownership of the attached popover wrapper's nonzero origin and synchronize only the hosted SwiftUI child to local bounds; prove the boundary with an isolated genuine `NSPopover.show(...)` regression.
- Prove native `T3/L11/B5/R2` becomes hosted `T3/L0/B5/R0`, the content occupies `x16…352/y21…297`, the filtered asymmetric raster matches a zero-inset baseline, and an intentionally unfiltered control moves.
- Give persistent Settings/workflow presentation a bounded non-key deadline, independently cancellable coalesced consumers, balanced activation accounting, red-close detach-before-cancel, and stale-completion identity checks. Cover same-MainActor-turn close→reopen directly.
- Replace fixed workflow columns and horizontal-only footers with measured grid/stack content and adaptive actions at the 520×360 minimum and simulated accessibility text. Preserve full profile-specific accessibility labels while selecting safe keyboard and heading/status accessibility focus targets.
- Record the current [UI/UX simplification and installed-app audit](UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md), including the final attached-wrapper root cause, installed screenshots/geometry, persistent-window clamps, async-generation ownership, package/safety evidence, and manual-accessibility boundary. Retain the [native UI structural reliability audit](UI-STRUCTURAL-RELIABILITY-AUDIT-2026-07-17.md) as preceding selective-safe-area, window-liveness, responsive-layout, and synthetic evidence.
- The final integrated gate passes 446 checks: 144 XCTest cases, 301 Swift Testing cases across 38 suites, and one separately executed native `NSPopover` regression. All build/Analyze/package/mount stages pass for `x86_64 arm64`; DMG SHA-256 is `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`.
- A separately authorized follow-up reinstalls the package to `/Applications` and verifies executable SHA-256 `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305`. Twenty measured popover opens have exact center delta `0`; Settings clamps `500×300` to `680×480` and retains `900×568` across ten normal opens; workflow clamps `500×300` to `520×392`, initially frames at `620×532` with `620×500` content, and closes with Escape.

The installed follow-up invoked no Apply, Capture, TCC, login-item, or system-setting mutation. Focused-control AX observation, push, CI, tag, notarization, and publication remain outside the completed evidence. VoiceOver was not run; full VoiceOver certification is excluded and unclaimed.

## M4.11 — bounded P2 UI refinement (completed locally)

- Make the pristine empty/idle tray's one Capture affordance a labelled body-level primary CTA while retaining one compact header action for nonempty and non-idle states.
- Keep **New Profile** as the direct management action and group Duplicate/Delete, Move Up/Down, and Import/**Export Saved Profiles…** behind one secondary menu. State directly that dirty unsaved changes are excluded, and export only `ProfileStore`'s persisted document.
- Replace ambiguous Included controls with **Apply with profile**, explicit Included/Not included text, non-color symbols, and setting-specific accessibility label/value/help.
- Replace relevant SwiftUI disclosures with an app-owned button disclosure that exposes localized Expanded/Collapsed value and next-action hint, owns expansion state at the screen, and removes collapsed children from the tree. Installed Return expands and Space collapses with AX value, hint, and child presence updated. VoiceOver was not run, was explicitly removed from P2 completion scope by the user on 2026-07-18, was restored disabled, and is not claimed. Full-app accessibility remains a separate nonblocking follow-up.
- Replace Advanced Diagnostics' former 700-point minimum with a 520×360 minimum and 640×460 ideal contained by Settings' 680×480 minimum. Add Korean accessibility-text fixtures for direct About, protected safety, long result, and long workflow error at 520×360, plus diagnostics and Settings/About at 680×480.
- Route every Settings/`⌘,` command synchronously to Profiles, including visible, close→reopen, and stale out-of-order presentation cases.
- Promote generic profile storage failures into a heading/icon/card with one context-valid Retry Loading or Dismiss Error action while keeping editor-owned errors single and nonduplicated.
- Record source, synthetic, installed, and accessibility boundaries in [P2-UI-REFINEMENT-AUDIT-2026-07-17.md](P2-UI-REFINEMENT-AUDIT-2026-07-17.md). The final integrated count is 461; the reviewed evidence contains 39 fixtures and 79 artifacts; DMG SHA-256 is `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`; the reinstalled executable SHA-256 is `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719`.

The P2 pass does not include profile-store path hardening, Apply/Capture execution, TCC, login approval/retry/reboot, Gatekeeper, physical Intel, diagnostics clearing, import/export interaction, or ColorSync/Core Audio/Ethernet/Wi‑Fi IPv4 mutation. Complete keyboard traversal and focused-control AX observation remain separate nonblocking manual evidence; full-app VoiceOver certification is excluded and unclaimed.

Release publication, push, Gatekeeper, physical Intel, required TCC testing, signing/notarization, and any live mutation-and-rollback procedure remain separate and require their own authorization boundaries in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md). Full VoiceOver certification is excluded and unclaimed, not a deferred release task.

## M6 — Open-source public beta release (local release controls verified; publication pending)

The first public beta remains bounded to the simple **Capture → Edit → Review & Apply** product flow. It does not add accounts, cloud services, telemetry, automatic profile switching, arbitrary shell execution, UI automation, private APIs, or a new plugin/SDK surface.

Baseline completed locally:

- Harden profile storage and import against traversal, symlinks, non-regular files, wrong ownership, oversized inputs, source replacement, and tested file-identity/TOCTOU races. Descriptor-bound reads and identity-bound quarantine/permission repair preserve fail-closed behavior without turning unrelated permission denial into an application-wide failure. Managed staging, commit, guarded rollback, cleanup, and sync now remain on one verified parent-directory descriptor; missing targets use exclusive rename and existing targets use atomic swap. Deterministic parent-path, regular/symlink leaf replacement, and both post-commit rollback tests preserve displaced objects. Documented residuals are Darwin's lack of inode-conditional rename/unlink against a noncooperative same-UID process and possible private old-leaf staging residue after abrupt interruption between swap and unlink, not a path-redirection fallback.
- Make launch at login explicitly opt-in. Reset the unverifiable pre-release automatic-registration state, remove stale registration, and preserve subsequent user choices with a versioned consent marker.
- Add a full-history public-release audit for credential patterns, concrete personal home paths, current-tree placeholders, historical PNG/JPEG/ICNS metadata, and commit/tag author, committer, and tagger email metadata; configure the unpushed local CI definition to run it from a full-history checkout. Already-public legacy identity metadata remains in immutable history without exposing its values in audit output or the exact-SHA exception file, while new published commits and annotated tags require GitHub noreply identities.
- Freeze the public-beta compatibility boundary in policy documentation: bundle and Keychain identities, SemVer/build/schema behavior, macOS 14.0 deployment target, planned initial Apple Silicon target, minimum-OS runtime evidence gate, and internal/unstable Swift library products.
- Add support, governance, compatibility, security, privacy, contribution, and distribution guidance. The local proposed manual signed-candidate workflow is limited to a Developer ID/notarized/stapled **draft prerelease**, attestations, draft redownload verification, and a workflow artifact; it is unpushed and unproven with credentials. The effective remote workflow remains unsafe for any release tag and must be replaced before release work begins.
- Fail closed on missing/non-integral profile schema versions, nil included ColorSync values, and snapshot capability-group mismatches without blocking unrelated snapshot groups. Preserve only the explicit schema 0→1 migration.
- Remove runtime coordinate collection/cache and its Settings refresh surface. Location authorization now exists only to read the current Wi-Fi SSID during an explicit Capture; imported location conditions remain dormant schema data.
- Keep the final Apply decision honest without complicating the flow: Apply Preview uses one review-to-decision scroll sequence with a localized text-and-shield Beta status stating that Apply and rollback are not hardware-verified and that users must check System Settings afterward. Decision actions follow the review content, Escape remains the cancel shortcut, and Apply is not a default Return-key action.
- Prepare the user-facing public surface locally: rewritten README, English/Korean user guides, profile-schema and adapter-contract references, launch copy, bilingual static site, and an exact-commit public-media pipeline. The currently tracked Capture/Edit/Review screenshots, silent captioned demo, deterministic social preview, eight-file public manifest, 11-file source/AX manifest, and provenance still bind source `f27c3f285d21b454cbd7326f704c45f29023048c`; regenerate them from the committed Apply Preview source before marking the current surface synchronized.
- Verify the site's privacy boundary locally: no project analytics, client tracking, project-set cookies, account, database, object storage, service binding, or download; disclose hosting-provider aggregate operations and the two pinned tab-scoped vinext router guards instead of claiming that no provider processing exists.
- Keep the holding site and its provenance-reviewed media in a dedicated CI gate: exact Node version, lockfile-only install with lifecycle scripts disabled, dependency-advisory audit, site build/lint/rendered-output tests, and complete public/source asset verification. The job is prepared locally and remains unpushed/unproven on the effective default branch.
- Keep the site renderer's launch switch data-only: closed-schema tracked metadata permits only `holding` with no release URL or `published` with the exact canonical `v0.1.0` GitHub Release URL. The immutable Release notes are self-contained and reject branch-lifecycle document links. The broader launch uses a locally pre-reviewed, unpushed public-copy finalization patch only after the Release is visibly public; it synchronizes both publication records, README, the English/Korean guide index and guides, PRIVACY, SUPPORT-MATRIX, SECURITY, SUPPORT, and required status records without component-code changes. Its review tree and protected-merge tree must match, and the exact two CI jobs must pass on both the review head and final `master` SHA before deployment. A deterministic closed-schema gate exercises valid holding/published fixtures and rejects stale, negated, one-language, wrong/mixed/general/direct-asset URL, unsafe CTA, or disabled-private-reporting copy across nine public surfaces. The tracked state remains `holding` and nothing was deployed.
- Pass integrated non-live `make verify` on 2026-07-21 with 4,736 deterministic checks/assertions: 507 app checks (183 XCTest, 323 default Swift Testing cases across 39 suites, and one isolated native popover case in a 40th Swift Testing suite) plus 4,229 release-tooling assertions (351 base release-policy, 659 remote-controls v1 policy/normalizer, 178 remote-controls v2 lifecycle-policy, 69 remote-controls v2 collector, 407 publication-approval policy, 1,106 external-beta/inventory/lineage/template policy, 129 collector-wrapper mock, 71 draft-reconciler mock, 246 artifact-restoration mock, 496 approved-publication mock, 306 legacy-workflow-containment mock, and 211 shell/workflow guard assertions). The latest regenerated unsigned development-evidence DMG SHA-256 is recorded in the completion ledger; the DMG is not byte-for-byte reproducible. The preceding 39-assertion complete-history audit must be rerun after the current source and media commits, and the release assertions do not prove a real inventory review, external tester result, credentialed signing/notarization, protected-remote, or publication run.
- Pass the local site build/lint/rendered-HTML tests, pinned dependency audit, public-asset checksum/metadata/video/caption checks, complete-history public-release audit, and integrated diff checks. No site, tag, release, or promotional post was published.
- Add an itemized [release evidence template](RELEASE-EVIDENCE-TEMPLATE.md), [external beta report](EXTERNAL-BETA-REPORT-TEMPLATE.md), curated English/Korean [`v0.1.0` notes](releases/v0.1.0.md), and immutable [incident/patch runbook](RELEASE-INCIDENT-RUNBOOK.md). The templates define required proof, while the notes contain copy only; neither makes a pending gate pass.
- Record the exact [remote release controls audit](REMOTE-RELEASE-CONTROLS-AUDIT-2026-07-18.md): the effective unsigned `v0.1.0` publication path, absent branch/tag/environment protections, empty repository secret/variable name lists, disabled immutable/private-reporting controls, pending one-maintainer reviewer-policy decision, stale repository metadata, and the approval-bound containment → feature branch → PR → read-back sequence. No credential value was inspected and no remote state was changed.
- Recheck that boundary with authenticated read-only GitHub queries on 2026-07-20 and 2026-07-21. Remote `master` remains `1489b7f`; the unsafe Release workflow remains active; no ruleset, environment, tag, Release, publication workflow, immutable-release setting, private-reporting path, credential-name configuration, or reviewed public metadata was added. This is current blocker evidence, not a passing final-pre-tag gate, and it changed no remote state.
- Add a local fail-closed legacy-workflow containment helper. Its GET-only plan makes two full anchored observations and writes an external owner-only receipt; a separately approved apply revalidates that exact receipt, performs two fresh observations, permits at most one fixed bodyless disable PUT, requires 204/empty plus two stable post-observations, and writes a separate success receipt. Already-disabled is a zero-PUT success; any post-PUT uncertainty is exit 75 with no automatic retry and the helper contains no enable/tag/Release/push path. GitHub CLI 2.95-compatible paginated projection and strict JSON-line canonicalization pass 306 local assertions. Authenticated GETs confirm that the unsafe workflow remains active; a private plan receipt is not remote containment.
- Extend the fail-closed remote-controls verifier into a two-phase lifecycle with strict synthetic fixtures and a read-only GitHub collector. It binds the exact candidate/draft, CI, and publication workflow identities/blobs plus the complete active-workflow inventory; both required CI checks, check runs, and jobs from one successful check suite and pinned workflow run; effective `master` and split release-tag rules; two protected environments; actor identities; separated credential-name scopes; Actions/security controls; and two fresh manual-record digests. `final-pre-tag` requires zero `v*` refs/Releases, while `pre-publication` requires the exact direct annotated-tag object and one exact draft prerelease. Every release-critical remote observation is collected twice and must normalize identically. The authoritative policy remains `configured:false` until its complete repository/workflow/operator/reviewer/publisher/approval identity is reviewed, and the two unavailable API facts remain separate Settings/manual gates.
- Make signed-draft preparation recoverable without rebuilding: preserve the exact nine assets in an immutable attempt-1 origin-run artifact before draft creation, then use a separate draft dispatch bound to the origin run, artifact ID, and archive digest. Verify the raw archive, exact files, signed candidate, and attestations before mutation; reject conflicting metadata/assets; and permit only additive upload of missing byte-identical assets before full redownload verification. The origin build run is never rerun, and no clobber, Release edit/delete/publication, or tag mutation is allowed.
- Add an approval-bound publication workflow and closed-schema policy that restore the exact attempt-1 candidate, prove the direct A→B evidence history and tag-bound digest, revalidate both approval-commit CI jobs plus the exact tag/draft/nine assets/attestations, actor and token ownership, remote-controls/manual evidence, canonical chronology, and immutable-release state immediately before one exact-ID PATCH. After the transition it verifies the public prerelease and re-downloads all nine assets. Any publication-side signal, cancellation, host loss, incomplete log, or ordinary failure after a PATCH attempt is explicitly incident-only. The policy and publisher assertions are local/mock evidence; no remote publication occurred.
- Replace the opaque three-digest beta gate with descriptor-bound `external-beta/v1` reports, a protected no-PII independence-review set, an actual-byte `candidate-inventory/v1`, canonical global integer build numbers, and `predecessor-lineage/v2`. Retained and non-retained protected runs have separate closed variants; gaps are allowed, but builds are unique and below the current candidate, run IDs and retained identities are unique, and every historical completion strictly predates the current manifest. Publication v2 uses the verifier's single descriptor-read result for the actual release-manifest, final-DMG provenance, inventory, lineage, set, ordered report, and Sonoma-report digests immediately before the sole PATCH. The first-beta upgrade row may be not applicable only when the reviewed inventory contains no installable retained predecessor. Remote-history completeness and real tester identity remain protected reviewer trust boundaries. This is deterministic local/mock policy evidence only—no inventory review, tester result, signing run, or publication has occurred.
- Add a policy-owned stdout-only rejected-placeholder generator for all eight closed inventory, lineage, report, and set shapes. Generated JSON uses the exact production key structure but reserved non-evidence values, false gates, invalid IDs/times/digests, and no host or candidate input; `verify-set` rejects it explicitly, and the public-history audit rejects a tracked sentinel under release evidence. This closes the operator-scaffolding gap without claiming an inventory review, tester result, or digest lineage.

Mandatory gates before public v0.1.0:

- Produce one canonical Developer ID/hardened-runtime build with unchanged signed-app identity through packaging, signed DMG, accepted notarization log, stapled artifact, app-and-DMG Gatekeeper validation, checksum, SBOM, attestation/provenance, and redownload verification.
- Replace the effective remote unsigned-publication workflow, protect the release environment/default branch, split `v*` creation authority from no-bypass update/deletion protection, enable immutable releases and private vulnerability reporting, and verify that no workflow can bypass human publication approval or move/delete an existing release tag.
- Merge the locally reviewed guides, support/security routes, and provenance-reviewed media before deploying the bilingual site; set approved canonical HTTPS/release URLs, complete a bounded manual browser and final bilingual-copy pass, then verify every public link from a clean session.
- Complete separate exact-candidate evidence for browser download and real extracted-DMG quarantine, Gatekeeper without Open Anyway, first launch/login default-off, recorded-predecessor upgrade or the strictly validated first-beta not-applicable state, schema 0→1 migration, backup recovery, import/export, diagnostics, uninstall, and optional app-owned data removal.
- Complete the protected candidate-history review plus three external Apple Silicon beta reports downloaded from the protected workflow artifact, their protected independence-review set and predecessor lineage, all bound to the identical final DMG SHA-256 and final-DMG provenance attestation, with at least one full exact-candidate lifecycle on macOS 14 Sonoma, zero public P0/P1 issues, and a confidential security-responder zero-blocker sign-off. Intel remains unclaimed until physical verification exists.
- Obtain the user's explicit approval for the final artifact, tag, release notes, site publication, and promotional posts. Until then, this milestone is **not a public release**.
- After the canonical GitHub Release exists, pass project-owned Homebrew tap `install`, `upgrade`, `uninstall`, and `zap` against its exact final SHA-256. Official Homebrew Cask submission remains a later milestone.

Full VoiceOver certification is intentionally excluded from this release goal and is not claimed. The bounded accessibility contract remains localized keyboard behavior, accessible names/values/help where implemented, and non-color state cues; full VoiceOver/rotor evidence may be pursued independently without blocking v0.1.0.
