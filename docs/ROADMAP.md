# Roadmap

The roadmap is evidence-based. “Implemented” means source exists; “verified” names the evidence boundary; “done” additionally requires current documentation and committed/pushed evidence. Dates are intentionally omitted because safety gates determine sequence.

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

The active implementation contract is [UI-REFINEMENT-GOAL.md](UI-REFINEMENT-GOAL.md). It prioritizes unsaved-draft protection, direct typed setting-value editing, a compact menu/apply hierarchy, legacy-condition compatibility, accessibility feedback, and English/Korean parity without changing adapter or mutation semantics.

Implemented and verified without live flags:

- App-lifetime saved/draft state with dirty detection, save/discard/cancel replacement protection, external-refresh preservation, authoritative metadata merge, fixed save/revert status, `⌘S`, ordinary-quit protection, and read-only capture into the draft
- Friendly included-value summaries and operation previews with technical details disclosed separately, preserved imported symbols, and deterministic localization at the UI boundary
- Compact top-right Capture plus icon-only Settings/Quit, a typed capture outcome, rejection of unusable snapshots, atomic profile creation/selection, and brief success-only feedback
- One primary Apply action and direct Edit per profile, with ellipsis, availability-review, available-items, and manual-refresh controls absent; disabled-reason text and symbols, bounded scrolling, all-disabled state, and automatic menu-open readiness refresh remain
- Group and option toggles that immediately expand concrete display/audio/network/input value editors, preserve disabled values, and identify unsupported display or administrative-network fields without relying on color
- Condition editing removed while persisted/imported conditions remain preserved, evaluated, and regression tested
- Separate app-desired and macOS login-item state, mismatch-only guidance, About links, text diagnostic severity, accessibility announcements, and display safety keyboard/value metadata
- English/Korean catalog parity, duplicate-key, placeholder, and static-key validation

Evidence: the current header/editor follow-up passes full local `make verify` with 215 default non-live tests: 112 XCTest with five skips plus 103 Swift Testing cases with one skip. The 56 presentation-specific cases are 29 draft XCTest cases and 27 presentation/condition Swift Testing cases. Universal builds, Analyze, DMG/checksum, mount, resources, architectures, and ad-hoc signature classification pass; local DMG SHA-256 is `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) remain the latest matching remote CI/artifact evidence and predate this follow-up. No live flag, screenshot capture, TCC action, Keychain write, or setting mutation was used.

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

## M5 — Packaging and CI (current local package and CI green)

- The 2026-07-11 post-fix full `make verify` locally passed lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI and tag-triggered release workflows are implemented; CI passed for repair commit `4e45328`
- Current header/editor follow-up `make verify` produced and verified a universal local DMG with SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`
- UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967); unsigned artifact ID `8256718472` verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`

Remaining:

- Perform a quarantined Gatekeeper/Open Anyway install on a clean user account or Mac
- Complete remaining non-mutating manual workflows, accessibility audit, and login approval/retry/reboot cases
- Publish a tag only after green CI and a current evidence ledger

## Current next task — non-mutating header and profile-editor walkthrough

Exercise the simplified menu header and direct setting editor with synthetic, non-personal data without broadening its safety scope.

- **Prerequisites:** launch a verified local build with synthetic profiles and keep every Apply, Capture, permission, login-item, and mutation action untouched.
- **Scope:** check the top-right Capture/Settings/Quit layout without activating Capture or Quit, Settings closed/open/minimized, direct Edit, dirty-draft Save/Discard/Cancel, group and option expansion, value preservation after off/on, unsupported notices, `⌘,`, English/Korean labels, and VoiceOver names.
- **Acceptance:** Settings always becomes visible on the Profiles tab, the requested profile is selected or protected by the dirty-draft decision, ellipsis/availability-review/available-items/manual-refresh controls stay absent, group and option expansion is clear, disabling and re-enabling preserves values, no condition editor is shown, and legacy condition data remains unchanged.
- **Verification:** record performed and unperformed cases separately, keep any screenshots synthetic and sanitized, update README/support/completion evidence, and run `make lint` plus `git diff --check` for evidence-only changes.

Release publication, Gatekeeper, physical Intel, full assistive-technology testing, and any live mutation-and-rollback procedure remain separate optional evidence work and require the authorization boundaries in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).
