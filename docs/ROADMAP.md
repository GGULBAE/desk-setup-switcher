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
- Profile and condition editors with permission-aware location UI

Evidence: mocks pass. All five opt-in read-only display, audio, network, input, and combined readiness-context tests pass on one Apple M5 Mac. A fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. External display, Ethernet, explicit denied/granted permutations, and physical Intel remain absent.

## M3 — Controlled application (mock verified; no live mutation evidence)

- Audio default/volume/mute, Wi-Fi power/saved association, and experimental input operations
- Network association preflight that requires target saved access and restorable current state; powered-on unreadable SSID is treated as ambiguous
- Core Graphics high-risk apply that starts app-only, promotes to session-only only after confirmation, and restores on timeout/revert/confirmation failure
- Fresh pre-execution plan/rollback validation, fatal reverse rollback, and conservative rollback of a failing operation that may have partially changed state
- Normal/force preview and itemized outcomes

Evidence: injected/mock success and fault tests pass. The fresh snapshot profile had a zero-operation plan and both Apply and Force Apply were disabled. **No live display, audio, network, mouse, or keyboard mutation and no live Keychain write has been run.**

## M4 — UX and release hardening (implemented; full local gate verified)

The active implementation contract is [UI-REFINEMENT-GOAL.md](UI-REFINEMENT-GOAL.md). It prioritizes unsaved-draft protection, human-readable setting summaries, clearer menu/apply hierarchy, safer condition entry, accessibility feedback, and English/Korean parity without changing adapter or mutation semantics.

Implemented and verified without live flags:

- App-lifetime saved/draft state with dirty detection, save/discard/cancel replacement protection, external-refresh preservation, authoritative metadata merge, fixed save/revert status, `⌘S`, ordinary-quit protection, and read-only capture into the draft
- Friendly included-value summaries and operation previews with technical details disclosed separately, preserved imported symbols, and deterministic localization at the UI boundary
- One primary Apply action, secondary review/available-items actions, disabled-reason text and symbols, bounded profile scrolling, all-disabled empty state, and readiness refresh progress
- Detected-device condition pickers, preserved disconnected values, advanced raw entry, typed IP/CIDR and location validation, and non-synthetic defaults
- Separate app-desired and macOS login-item state, mismatch-only guidance, About links, text diagnostic severity, accessibility announcements, and display safety keyboard/value metadata
- English/Korean catalog parity, duplicate-key, placeholder, and static-key validation

Evidence: the current UI-hardening tree passes full local `make verify` with 214 default non-live tests: 111 XCTest with five skips plus 103 Swift Testing cases with one skip. The 55 presentation-specific cases are 28 draft XCTest cases and 27 presentation/condition Swift Testing cases. Universal builds, Analyze, DMG/checksum, mount, resources, architectures, and ad-hoc signature classification pass; the local DMG SHA-256 is `6413e352b3d170b82510b7125f3f8cd0f52b9e5140bfa0977801887d09340e68`. No live flag, current-run screenshot capture, TCC action, Keychain write, or setting mutation was used.

Historical evidence retained from the 2026-07-11 baseline:

- Fresh `/Applications` launch as a background-only/menu-bar-only app; Korean popover and Settings rendering
- One accessibility-label inspection
- Default-on login-item registration, enabled status, UI opt-out, re-enable, and final disabled cleanup

Remaining before this milestone is done:

- Commit and push the complete milestone, then require green GitHub Actions and unsigned-artifact upload on that exact SHA
- Perform a current-tree non-mutating English/Korean layout and keyboard walkthrough with synthetic data if a safe evidence path is available
- Manually verify approval-required and failure/retry login-item states plus actual login-at-boot after a reboot
- Complete the full English/Korean walkthrough
- Run full VoiceOver, keyboard-only, focus, contrast, text-size, destructive-action, and permission-denial audits
- Manually verify import/export replacement/no-overwrite and diagnostics clearing
- Decide whether diagnostic export belongs in 0.1.0

## M5 — Packaging and CI (current local package green; current CI pending)

- The 2026-07-11 post-fix full `make verify` locally passed lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI and tag-triggered release workflows are implemented; CI passed for repair commit `4e45328`
- Current UI-tree `make verify` produced and verified a universal local DMG with SHA-256 `6413e352b3d170b82510b7125f3f8cd0f52b9e5140bfa0977801887d09340e68`

Remaining:

- Record the current UI commit's CI run and unsigned-package upload
- Perform a quarantined Gatekeeper/Open Anyway install on a clean user account or Mac
- Complete remaining non-mutating manual workflows, accessibility audit, and login approval/retry/reboot cases
- Publish a tag only after green CI and a current evidence ledger

## Current next task — UI refinement closure

Close [UI-REFINEMENT-GOAL.md](UI-REFINEMENT-GOAL.md) without broadening its safety scope:

- Commit and push the intended milestone, then require green CI and unsigned-package upload on the same final SHA.
- Keep full assistive-technology, TCC, login approval/reboot, Gatekeeper, physical Intel, Keychain, and live mutation evidence explicitly pending unless separately authorized and actually performed.

Release publication, Gatekeeper, physical Intel, full assistive-technology testing, and any live mutation-and-rollback procedure remain separate optional evidence work and require the authorization boundaries in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).
