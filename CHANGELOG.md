# Changelog

All notable changes will be documented here. The project follows Keep a Changelog structure and intends to use Semantic Versioning after the first public release.

## [Unreleased]

### Added

- Product requirements, technical specification, architecture, privacy policy, support matrix, roadmap, and evidence-based completion checklist.
- Initial contribution, conduct, security, issue, pull-request, distribution, and asset-provenance documentation.
- Native macOS 14 menu-bar app, Settings scene, login-item preference, English/Korean resource bundles, and original application icon.
- Versioned profile models, semantic/resource validation with value-safe actionable errors, schema migration, CRUD/order, permission-restricted atomic Application Support storage, backup/quarantine recovery, and validated import/export.
- Capability-driven display, audio, network, and experimental input adapters with read-only snapshots, planning, typed omissions/results, and rollback payloads.
- Readiness conditions for display, audio, USB/hardware, SSID, Ethernet, IPv4/IPv6 CIDR, and authorized recent location.
- Normal/force previews, fresh pre-execution plan/rollback validation, deterministic transaction ordering, conservative fatal rollback, and timed high-risk confirmation.
- App-only temporary display apply with session-only confirmation commit, plus Wi-Fi saved-access/rollback preflight and powered-on nil-SSID ambiguity handling.
- Keychain-backed secret boundary and local redacted/rotating diagnostics with Settings browsing and clearing.
- Deterministic Xcode project generation, Swift Package targets, Makefile verification commands, ad-hoc-integrity universal DMG/checksum tooling, and CI/release workflows.
- Unit and mock integration coverage plus opt-in read-only hardware smoke tests.

### Status

- Pre-release 0.1.0 implementation candidate; no public artifact or release yet.
- Final local `make verify` passed on 2026-07-11 with 158 tests (83 XCTest + 75 Swift Testing), universal Debug/Release builds, Analyze, DMG/checksum, mount, resources, and ad-hoc signature verification; six opt-in cases skip by default.
- All five opt-in read-only display/audio/network/input/readiness gates passed on an Apple M5 Mac running macOS 26.5.2. The final universal no-Developer-ID DMG has SHA-256 `3f99ebcea13ea1495e9c2471a45f66dacb851e3ba6670ce16aa84f48b26b99b7`.
- A fresh install from that DMG to `/Applications` launched background-only/menu-bar-only; Korean popover/Settings and an accessibility label passed. It created one schema-v1 **Ready** profile from a read-only snapshot with all four groups, with Apply and Force Apply disabled for the zero-operation plan.
- Default-on `SMAppService` registration succeeded with Background Task Management `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history.
- No live display, audio, network, mouse, or keyboard mutation and no live Keychain write has been run. Physical Intel, Gatekeeper/quarantine, approval-required and retry login-item paths, actual login-at-boot after a reboot, full accessibility/manual flows, pushed CI, and release publishing remain pending.
- Developer ID signing and notarization are optional and absent; the packaged app's ad-hoc signature is integrity-only.
