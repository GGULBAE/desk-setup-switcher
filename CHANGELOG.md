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
- Pure state-aware Apply, dirty-apply decision, capture-summary, read-back result-summary, and field-validation presentation models with deterministic synthetic regression coverage.
- Typed complete/partial capture feedback and compact itemized apply results, including a distinct `not verified` classification when a fresh read-only plan still requires an operation that an adapter reported as applied or the read-back preparation itself is unavailable.
- Per-profile destructive menu controls with named accessibility metadata and confirmation before deletion.

### Changed

- Profile editing now keeps an app-lifetime saved/draft distinction, protects replacement and ordinary quit paths with save/discard/cancel, preserves dirty edits across external refreshes, merges current non-editable metadata on save, and puts current-settings capture into the draft until the user saves.
- The editor now keeps save/revert status outside scrolling content, supports `⌘S`, summarizes included values instead of option counts, hides technical identifiers behind disclosures, and uses a curated icon picker without rewriting imported symbols.
- The profile editor now uses wider, individually padded cards instead of a dense `Form`; the fixed sidebar is narrower and expanded option rows retain readable English/Korean titles at standard, minimum, and simulated large-text sizes.
- Setting-group/option inclusion is independent from disclosure, so collapsing an included setting does not alter application state. Typed pickers and semantic sliders replace avoidable raw input; display-mode choices come from a typed ephemeral read-only catalog and are not added to profile JSON. Unsupported rotation/active-state and administrative-network values are presented as read-only snapshot data. Disabling a group or supported option still preserves its configured value.
- The menu keeps compact Capture and icon-only Settings/Quit controls in the top-right header and removes per-profile ellipsis, separate availability review, and manual refresh. The one primary row action is state-aware: complete plans open normal Apply and partial plans with executable operations open Apply Available, each through explicit preview.
- Apply checks app-lifetime dirty drafts before planning. Save-and-apply, discard-and-apply, and cancel preserve the existing draft contract and never silently execute a stale stored profile.
- Apply previews use friendly value descriptions and progressive technical details with adaptive sizing. Results are summarized per profile and item, followed by read-only replanning so an operation that remains necessary—or cannot be read back reliably—is not finalized as applied. Rollback reconciliation uses operation UUIDs so a rollback replaces only its matching success, and a successfully rolled-back failure remains an apply failure.
- Display rotation/active state and administrative IPv4/DNS/proxy values are preserved but normalized to excluded snapshot-only leaves at capture, local-load, and import boundaries. Empty unsupported-only groups are excluded without deleting captured values.
- Condition editing remains absent. Existing/imported conditions are preserved for schema round trips but are dormant compatibility data and do not block current manual readiness, preview, or application; automatic condition switching is not added.
- Capture feedback distinguishes complete, partial, and failure outcomes and counts saved, snapshot-only, unreadable, permission-required, and unsupported items. A disclosure explains each incomplete category with sanitized item names and no captured values, SSIDs, credentials, runtime device identifiers, or other raw sensitive values.
- Draft save validation reports field-specific required/range/format errors before persistence and associates localized non-color/accessibility error metadata with the affected control.
- Profiles/System/About replace the former four-tab Settings navigation. System keeps login and required permission guidance visible; diagnostics move to an on-demand advanced troubleshooting sheet with text severity. About retains source, issues, license, and privacy links; display safety retains default/Escape shortcuts and a remaining-time accessibility value.
- Profile deletion confirmation now expands inside its menu profile card instead of presenting a system confirmation dialog that can dismiss the MenuBarExtra before the user can respond. Cancel and `Esc` clear only the pending confirmation.

### Status

- The tray/editor follow-up passed integrated non-live `make verify` on 2026-07-14: lint/localization policy, 298 default cases (129 XCTest plus 169 Swift Testing cases, six opt-in skips), zero failures, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted-package inspection, and ad-hoc signature classification. The separate five-case opt-in live-read smoke gate also passed without mutation.
- Its verified `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` contains `x86_64 arm64` and has SHA-256 `273155843df1260ffb7555fe447d895e95696c95c28247fb023ad8f8ee2d39eb`. Twelve final-source English/Korean PNGs and twelve read-only AX logs passed visual, structural, and privacy review. The existing `/Applications` bundle was completely replaced from the DMG; the installed binary matched and launched without UI automation or setting mutation. No push or new CI run was performed.
- The apply-reliability follow-up passed integrated non-live `make verify` on 2026-07-14: lint/localization policy, 290 default cases (124 XCTest with five opt-in skips plus 166 Swift Testing cases with one opt-in skip), zero failures, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted-package inspection, and ad-hoc signature classification. Separately, `git diff --check` passed. No live flag was set.
- Its verified `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` contains `x86_64 arm64` and has SHA-256 `417ffbb20b6a77b9037f42d5acb998574460374675e746715474e17f9f772615`. The app is ad-hoc signed for integrity only, with no Developer ID or notarization. The behavior-focused local commit and clean status are reported in the handoff; no push or new CI run was performed.

- Pre-release 0.1.0 implementation candidate; no public artifact or release yet.
- The preceding header/editor tree passed full local `make verify` with 215 default non-live tests: 112 XCTest with five opt-in skips and 103 Swift Testing cases with one opt-in skip. The 56 presentation-specific cases comprised 29 profile-draft XCTest cases and 27 presentation/condition Swift Testing cases.
- Its universal Debug/Release, Analyze, DMG/checksum, mounted-image resource/architecture, and ad-hoc signature verification passed; that historical local DMG SHA-256 is `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b`. UI-hardening commit `5f0cabc` and [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967) remain the latest remote CI evidence and uploaded artifact ID `8256718472`; they predate the current apply-reliability follow-up. No current-follow-up screenshot walkthrough, full keyboard/VoiceOver audit, TCC matrix, hardware mutation, or live Keychain test has been run.
- Final local `make verify` passed on 2026-07-11 with 158 tests (83 XCTest + 75 Swift Testing), universal Debug/Release builds, Analyze, DMG/checksum, mount, resources, and ad-hoc signature verification; six opt-in cases skip by default.
- All five opt-in read-only display/audio/network/input/readiness gates passed on an Apple M5 Mac running macOS 26.5.2. The post-fix universal no-Developer-ID DMG has SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`.
- A fresh install from that DMG to `/Applications` launched background-only/menu-bar-only; Korean popover/Settings and an accessibility label passed. It created one schema-v1 **Ready** profile from a read-only snapshot with all four groups, with Apply and Force Apply disabled for the zero-operation plan.
- Default-on `SMAppService` registration succeeded with Background Task Management `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history.
- Initial Actions run `29154880831` for milestone `0d8f510` failed under Xcode 16.4/Swift 6.1.2 on the `NetworkSystemAPI` actor-isolation diagnostic. Repair commit `4e45328` extracts Sendable values before coalescing and is pushed; [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) succeeded on 2026-07-11 under macOS 15 with full `make verify` and unsigned-package upload passing.
- Downloaded CI artifact ID `8249295840` verified its checksum file and CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. This is distinct from local post-fix DMG SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; the DMGs are not byte-for-byte reproducible.
- No live display, audio, network, mouse, or keyboard mutation and no live Keychain write has been run. Physical Intel, Gatekeeper/quarantine, approval-required and retry login-item paths, actual login-at-boot after a reboot, full accessibility/manual flows, release tagging, and publishing remain pending.
- Developer ID signing and notarization are optional and absent; the packaged app's ad-hoc signature is integrity-only.
