# Desk Setup Switcher

> **Pre-alpha:** this repository is being built from an initial placeholder. There is not yet an installable release, and no system-setting capability is currently claimed as verified.

Desk Setup Switcher is a planned free and open-source macOS menu-bar app for manually saving and applying display, audio, network, mouse, and keyboard profiles. It is local-first: no account, server, cloud sync, telemetry, analytics, or automatic profile switching.

## Intended experience

- Capture the current Mac as an editable profile.
- See whether a profile is **Ready**, **Partial**, or **Unavailable** for the connected desk.
- Preview a normal or explicitly confirmed force apply.
- Apply only supported settings, record item-level results, and roll back safe completed steps after fatal failure.
- Keep credentials in Keychain and all other app data and redacted diagnostics local.

The authoritative scope is [docs/PRODUCT.md](docs/PRODUCT.md). Architecture and safety boundaries are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/TECHNICAL-SPEC.md](docs/TECHNICAL-SPEC.md).

## Current status

Milestone 0 is establishing the product contract, repository standards, and evidence ledger. The next milestone adds the Xcode project, runnable menu-bar shell, safe profile core, transaction engine, and mock tests. No live system mutation will be enabled before those boundaries pass verification.

Progress is tracked in:

- [Roadmap](docs/ROADMAP.md)
- [Completion criteria](docs/COMPLETION-CRITERIA.md)
- [Support matrix](docs/SUPPORT-MATRIX.md)
- [Changelog](CHANGELOG.md)

## Platform and principles

- Native Swift and SwiftUI
- macOS 14 Sonoma or later
- Apple Silicon and Intel targets
- Menu-bar-only app with `SMAppService` login item
- Public macOS APIs on the supported path
- Explicit experimental labels where an otherwise safe preference has no documented key contract
- No runtime Homebrew or third-party CLI requirement
- Unsigned DMG as the baseline release artifact; signing/notarization optional
- MIT licensed

## Development

Xcode 16 or later with a macOS 14+ SDK is the intended prerequisite. The repository will expose consistent `build`, `test`, `lint`, `analyze`, `package`, `verify`, and `clean` commands during Milestone 1. They are not documented as runnable until the project and scripts are committed and verified.

The local audit used Xcode through a process-level override because the active developer directory points to Command Line Tools:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

Project scripts will detect that case without modifying global `xcode-select` state.

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. CI and live tests must never change the host Mac's settings.

## Privacy and security

Read [docs/PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](SECURITY.md). Exported profiles can include user-chosen device/network labels and should be reviewed before sharing. They must never contain Wi-Fi passwords.

## Distribution

There is no release artifact yet. The planned unsigned DMG, Gatekeeper instructions, and optional Developer ID path are documented in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## License

[MIT](LICENSE) © 2026 GGULBAE.
