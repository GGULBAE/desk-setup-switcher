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

Evidence: mocks pass. All five opt-in read-only display, audio, network, input, and combined readiness-context tests pass on one Apple M5 Mac. A fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. External display, Ethernet, explicit denied/granted permutations, and physical Intel remain absent.

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

## M4.2 — Final-source synthetic UI audit (locally verified; interaction gaps recorded)

- DEBUG-only English/Korean audit fixtures cover menu overview, editor, validation, denied-permission presentation, diagnostics, minimum layout, and simulated large text
- The audit model uses a temporary store and injected empty adapters while blocking capture, apply, profile persistence, readiness, login-item, diagnostic, and Core Location request paths
- Settings switches at a fixed 760-point breakpoint between horizontal and vertical `AnyLayout` arrangements; the former draggable split divider is intentionally no longer part of the UX
- Category and option titles receive explicit width priority, while each Include label/switch is a compact fixed-width control, preventing `Form` alignment from vertically compressing Audio rows in Korean
- Profile rows expose one combined accessibility description instead of duplicate name/state elements
- Runtime localization tests load English and Korean bundles deterministically and assert exact formatted output
- Each menu profile now has a directly visible, named Delete control with inline confirmation that remains inside the MenuBarExtra and expands the list viewport enough to keep both actions visible, including Cancel/`Esc` and dirty-draft discard handling
- Capture now requests Location only after an explicit Capture action and privacy explanation, routes denied access to macOS System Settings or an explicit Wi-Fi-free path, and reports only applicable settings plus actionable permission gaps. Snapshot-only, unreadable, and unsupported evidence no longer creates user-facing partial-capture noise, and the always-unsupported service-order query is absent
- The profile editor replaces dense `Form` alignment with wider cards and a narrower fixed sidebar, while Settings reduces four primary tabs to Profiles/System/About and exposes diagnostics as an on-demand troubleshooting sheet

Evidence: the [manual UI audit](MANUAL-UI-AUDIT-2026-07-14.md) records 12 PNGs and 12 nonempty read-only AX logs from before the inline-delete and actionable capture-permission follow-ups. Static English/Korean standard, 680×480 minimum, simulated `.accessibility3`, validation, System, and advanced-diagnostics states passed visual, AX-structure, and privacy review at that source point. Current deterministic tests inject both the macOS authorization request and System Settings open action, while synthetic audit mode proves both remain suppressed. The latest full non-live gate and package checksum are recorded after verification; a user-driven current TCC click-through remains pending.

The actual MenuBarExtra Settings click/reopen path and same-window 980→680→980 selection/disclosure/unsaved-value/focus preservation remain pending because no user result was supplied and no UI automation was substituted. Full keyboard-only, VoiceOver, real macOS text-size, TCC, login approval/retry/reboot, Keychain, Gatekeeper, physical Intel, import/export, and mutation/rollback evidence also remains pending.

## M5 — Packaging and CI (current local package verified; historical CI green)

- The 2026-07-11 post-fix full `make verify` locally passed lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI and tag-triggered release workflows are implemented; CI passed for repair commit `4e45328`
- Current header/editor follow-up `make verify` produced and verified a universal local DMG with SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`
- UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); unsigned artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`
- The 2026-07-14 apply-reliability `make verify` produced and mounted its then-current universal package with SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`; this is historical package evidence
- The capture-permission follow-up `make verify` produced and mounted the current `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`, verified `x86_64 arm64`, resources, checksum, and ad-hoc/no-Developer-ID signature status; SHA-256 is `8760d68754f3bc1eebca37319bd0d2bfc29b6b3d90832532e0a64cd072506a9b`. The preceding tray/editor SHA-256 `f3d24ae95709d0db9de13ba6032eb63a1d19a5be89af15aa68244da9019afbde` and layout-correction SHA-256 `ae940ce1cffb969f309b8ffa8f6ffcd0637fd0845ee21bf24fa59129ea530ef7` are historical

Remaining:

- Perform a quarantined Gatekeeper/Open Anyway install on a clean user account or Mac
- Complete remaining non-mutating manual workflows, accessibility audit, and login approval/retry/reboot cases
- Publish a tag only after green CI and a current evidence ledger

## Current next task — optional manual and release evidence

The implementation, static English/Korean layout/AX audit, live-read smoke gate, and non-live package gate are complete locally. The next useful evidence is a user-driven actual MenuBarExtra Settings click/reopen and same-window resize state/focus check, followed by a keyboard-only and VoiceOver walkthrough. Import/export, permission, login approval/retry/reboot, and Gatekeeper checks remain under their documented authorization boundaries. A push, new CI run, tag, or publication is a separate operator decision and was not part of this local goal.

Release publication, push, Gatekeeper, physical Intel, full VoiceOver/TCC testing, signing/notarization, and any live mutation-and-rollback procedure remain separate and require their own authorization boundaries in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).
