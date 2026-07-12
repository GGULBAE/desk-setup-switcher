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
- A pure `DeskSetupPresentation` target with deterministic profile-draft, value-summary, menu-action, operation-preview, condition-choice, and condition-validation coverage.
- English/Korean catalog validation for key parity, duplicate keys, format placeholders, and statically discoverable localized UI keys.

### Changed

- Profile editing now keeps an app-lifetime saved/draft distinction, protects replacement and ordinary quit paths with save/discard/cancel, preserves dirty edits across external refreshes, merges current non-editable metadata on save, and puts current-settings capture into the draft until the user saves.
- The editor now keeps save/revert status outside scrolling content, supports `⌘S`, summarizes included values instead of option counts, hides technical identifiers behind disclosures, and uses a curated icon picker without rewriting imported symbols.
- Setting groups now expand when enabled, and each enabled option expands its concrete display, audio, network, or input value editor; disabling a group or option preserves its configured value. Unsupported display and administrative-network values remain editable for snapshot compatibility but carry explicit non-color support notices.
- The menu moves compact Capture and icon-only Settings/Quit controls to the top-right header, removes the per-profile ellipsis and availability-review/available-items/manual-refresh UI, and shows capture success only briefly after an actual success. Profile capture rejects snapshots without a usable payload and creates plus selects the profile in one atomic store update.
- Apply previews use friendly value descriptions and progressive technical details with adaptive sizing; internal review-only/normal/available-items states remain regression tested without being exposed by the simplified menu.
- Condition editing is no longer exposed. Existing and imported conditions remain stored and evaluated for backward compatibility; pure condition choice and validation tests remain regression coverage rather than current-UI evidence.
- Permissions distinguish the app's desired login-item setting from macOS registration state; About links to source, issues, license, and privacy; diagnostics include text severity; display safety adds default/Escape shortcuts and a remaining-time accessibility value.

### Status

- Pre-release 0.1.0 implementation candidate; no public artifact or release yet.
- The current header/editor tree passes full local `make verify` with 215 default non-live tests: 112 XCTest with five opt-in skips and 103 Swift Testing cases with one opt-in skip. The 56 presentation-specific cases comprise 29 profile-draft XCTest cases and 27 presentation/condition Swift Testing cases.
- Universal Debug/Release, Analyze, DMG/checksum, mounted-image resource/architecture, and ad-hoc signature verification pass; the current local DMG SHA-256 is `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) remain the latest matching CI evidence and uploaded artifact ID `8256718472`; they predate this local follow-up. No current-tree screenshot walkthrough, full keyboard/VoiceOver audit, TCC matrix, hardware mutation, or live Keychain test has been run.
- Final local `make verify` passed on 2026-07-11 with 158 tests (83 XCTest + 75 Swift Testing), universal Debug/Release builds, Analyze, DMG/checksum, mount, resources, and ad-hoc signature verification; six opt-in cases skip by default.
- All five opt-in read-only display/audio/network/input/readiness gates passed on an Apple M5 Mac running macOS 26.5.2. The post-fix universal no-Developer-ID DMG has SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`.
- A fresh install from that DMG to `/Applications` launched background-only/menu-bar-only; Korean popover/Settings and an accessibility label passed. It created one schema-v1 **Ready** profile from a read-only snapshot with all four groups, with Apply and Force Apply disabled for the zero-operation plan.
- Default-on `SMAppService` registration succeeded with Background Task Management `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history.
- Initial Actions run `29154880831` for milestone `0d8f510` failed under Xcode 16.4/Swift 6.1.2 on the `NetworkSystemAPI` actor-isolation diagnostic. Repair commit `4e45328` extracts Sendable values before coalescing and is pushed; [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) succeeded on 2026-07-11 under macOS 15 with full `make verify` and unsigned-package upload passing.
- Downloaded CI artifact ID `8249295840` verified its checksum file and CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. This is distinct from local post-fix DMG SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; the DMGs are not byte-for-byte reproducible.
- No live display, audio, network, mouse, or keyboard mutation and no live Keychain write has been run. Physical Intel, Gatekeeper/quarantine, approval-required and retry login-item paths, actual login-at-boot after a reboot, full accessibility/manual flows, release tagging, and publishing remain pending.
- Developer ID signing and notarization are optional and absent; the packaged app's ad-hoc signature is integrity-only.
