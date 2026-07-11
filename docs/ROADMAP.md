# Roadmap

The roadmap is evidence-based. “Done” means committed verification exists and [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) is updated. Dates are intentionally omitted; safety gates determine sequence.

## M0 — Repository and product contract (in progress)

- Product requirements, technical specification, architecture, privacy policy, support matrix, and completion ledger
- Governance, contribution, security, issue/PR, and distribution documentation
- Truthful README with pre-alpha status
- Development toolchain baseline

Exit gate: documents agree on scope and do not claim unimplemented behavior; Markdown/link and repository hygiene checks pass.

## M1 — Safe core and runnable shell

- Xcode app project and Swift package core targeting macOS 14
- Menu-bar-only app shell, Settings scene, English/Korean resources, `SMAppService` status/control
- Versioned profiles, validation, CRUD, ordering, atomic store, backup/quarantine, import/export
- Adapter protocol and capability model
- Condition evaluation, CIDR, stable identity matching
- Apply planning and transaction engine with reverse rollback
- Mock adapters and unit/integration tests

Exit gate: Debug/Release builds, core tests, mock integration tests, lint, and analyze pass without changing real settings.

## M2 — Read-only discovery and profile editing

- Core Graphics display discovery and stable fingerprints
- Core Audio UID discovery and control capability probing
- Network/interface/IP/DNS/gateway discovery with permission-safe SSID behavior
- Common mouse/keyboard preference snapshot with experimental labels where necessary
- Snapshot results and complete profile editor
- Readiness states and condition editor

Exit gate: safe live snapshot smoke tests plus mocks; denied permissions and absent devices degrade correctly.

## M3 — Controlled application

- Audio default/volume/mute operations
- Wi-Fi power and saved-network association where public API/capability allows
- Safe common input preference operations
- Core Graphics topology/mode apply, backup, reverse rollback, timed confirmation
- Normal/force preview and itemized result UI
- Keychain integration for any credential reference

Exit gate: all mutations have validation, no-op filtering, rollback semantics, mock fault tests, and explicit opt-in hardware procedures. Hardware-unverified rows remain labelled as such.

## M4 — UX and release hardening

- Full CRUD/reorder/snapshot/import/export UI
- Accessibility and Korean localization audit
- Diagnostics, rotation/redaction, permission explanations
- App icon and distributable asset provenance
- New-user and troubleshooting documentation

Exit gate: clean accessibility/localization review, full regression verification, no sensitive fixture/log data.

## M5 — Packaging and release

- Reproducible unsigned universal DMG with Applications link
- SHA-256 checksum and artifact verification
- Tag-based GitHub Actions release workflow
- Optional Developer ID signing/notarization path
- Clean working tree, pushed milestones, green Actions

Exit gate: every mandatory completion-ledger row has evidence or an accurately documented hardware limitation with mocks, capability checks, and a manual procedure; no mandatory implementation work remains.

## Current next task

Complete M0, commit and push it, then implement M1 as a buildable vertical slice. Do not enable live system mutations during M1.
