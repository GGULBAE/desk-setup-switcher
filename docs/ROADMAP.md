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

## M4 — UX and release hardening (in progress)

Implemented or partially verified:

- CRUD/reorder/snapshot/import/export/apply UI, permission explanations, diagnostics browsing/clear, icon, localization catalogs, accessibility labels, and keyboard shortcuts
- Fresh `/Applications` launch as a background-only/menu-bar-only app; Korean popover and Settings rendering
- Accessibility-label inspection
- Default-on login-item registration, enabled status, UI opt-out, re-enable, and final disabled cleanup

Remaining:

- Manually verify approval-required and failure/retry login-item states plus actual login-at-boot after a reboot
- Complete the full English/Korean walkthrough
- Run full VoiceOver, keyboard-only, focus, contrast, text-size, destructive-action, and permission-denial audits
- Manually verify import/export replacement/no-overwrite and diagnostics clearing
- Decide whether diagnostic export belongs in 0.1.0

## M5 — Packaging and CI (pushed and green; publication pending)

- Post-fix full `make verify` locally passes lint, 158 tests (83 XCTest + 75 Swift Testing), universal builds, Analyze, packaging, checksum, and mounted-image inspection
- Versioned DMG contains universal app, `/Applications` link, resources, and a verified ad-hoc integrity signature
- Local post-fix DMG SHA-256 is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`
- CI artifact ID `8249295840` verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; the DMGs are not byte-for-byte reproducible
- The artifact is correctly classified as no Developer ID and not notarized
- CI and tag-triggered release workflows are implemented; CI passed for repair commit `4e45328`

Remaining:

- Perform a quarantined Gatekeeper/Open Anyway install on a clean user account or Mac
- Complete remaining non-mutating manual workflows, accessibility audit, and login approval/retry/reboot cases
- Publish a tag only after green CI and a current evidence ledger

## Current next task — optional manual evidence and release publishing

Choose and execute only the remaining evidence needed for a release decision:

- Release scope: decide whether to publish 0.1.0; if proceeding, run the selected Gatekeeper, login-item, non-mutating workflow, localization, and accessibility checks, then create the tag/release only from an accepted green commit.
- Optional hardware scope: repeat safe launch/read-only coverage on physical Intel when available. Run any live display/audio/network/input mutation-and-rollback procedure only with separate explicit approval and the preflight/rollback controls in [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md).
- Non-goals: automatic switching, Developer ID/notarization without release credentials, vendor settings, private APIs, or inferring unrun hardware results.
- Validation: preserve the green implementation evidence for `4e45328`, record redacted results for each authorized manual case, verify any published artifact/checksum independently, and refresh README/support/completion evidence. A mock or read-only result never satisfies a mutation row.
