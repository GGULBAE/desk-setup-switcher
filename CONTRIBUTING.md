# Contributing

Thanks for helping build Desk Setup Switcher. The project is a pre-release 0.1.0 implementation candidate and prioritizes safety, privacy, testability, and honest capability reporting.

## Before starting

1. Read [docs/PRODUCT.md](docs/PRODUCT.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), and [AGENTS.md](AGENTS.md).
2. Check [docs/ROADMAP.md](docs/ROADMAP.md) and existing issues.
3. Discuss changes that expand scope, add a permission, use a non-public contract, or alter distribution/privacy behavior.

Use full Xcode with a Swift 6.1-or-later toolchain. The project targets macOS 14 or later and checks a universal `arm64 x86_64` Xcode app. Physical runtime evidence currently covers Apple Silicon only; an `x86_64` cross-build is not an Intel support claim.

General use questions belong in [SUPPORT.md](SUPPORT.md). Roles, decision authority, triage, and release approval are defined in [GOVERNANCE.md](GOVERNANCE.md). Suspected security problems must follow [SECURITY.md](SECURITY.md) and must never be described in a public issue.

## Canonical commands

```sh
make build
make test
make lint
make analyze
make audit-public-release
make verify-public-surface
make package
make verify-package
make verify
make clean
```

`make verify` is the required app gate. It runs source-policy and formatting checks, the default unit/mock suite, Swift and universal Xcode Debug/Release builds with warnings as errors, Xcode Analyze, no-Developer-ID DMG packaging, SHA-256 validation, and mounted-image inspection. `make audit-public-release` separately scans the complete Git history and image metadata for high-confidence credential and personal-path patterns while suppressing matched values; run it from a full, non-shallow checkout before preparing anything public. Changes to `site/`, public media, or their provenance must also run `make verify-public-surface` after installing the lockfile-pinned site dependencies with lifecycle scripts disabled. That public-media gate requires `ffmpeg` and `ffprobe` as development-only inspection tools; CI supplies them through Homebrew `ffmpeg@7`, while the app and deployed site have no Homebrew or FFmpeg runtime dependency.

The read-only live discovery tests require an explicit opt-in and still do not change settings:

```sh
DESK_SETUP_LIVE_READ_TESTS=1 make test
```

The Keychain round trip has a separate write gate and is not part of normal verification. Live display, audio, network, mouse, or keyboard mutation must never be added to an ordinary test or CI job.

## Development expectations

- Keep SwiftUI/AppKit in the app layer, pure domain logic in `DeskSetupCore`, and macOS framework effects behind `DeskSetupSystem` adapters.
- Do not introduce a runtime dependency on Homebrew or another CLI.
- Do not add application-owned outbound traffic, telemetry, accounts, cloud storage, automatic switching, arbitrary shell execution, UI automation, or private APIs.
- Re-read current system state immediately before an apply and never execute a preview whose operations or rollback payloads became stale.
- Keep high-risk display changes app-only until explicit confirmation and preserve rollback behavior for failure, timeout, confirmation failure, and termination.
- Treat a powered-on Wi-Fi interface with no readable SSID as ambiguous; never assume it is safely disassociated. Require saved target and rollback preflight before planning association.
- Add deterministic tests for success, capability limitation, permission denial, no-op behavior, partial/fatal failure, stale state, and rollback where relevant.
- Use synthetic device/network/location data in tests and screenshots.
- Keep user-facing copy localizable in English and Korean and update README, roadmap, support matrix, and completion evidence with behavior changes.
- Treat the Swift library products as internal, unstable implementation boundaries. Do not advertise a public SDK or compatibility guarantee without first changing the compatibility policy and adding its tests and documentation.

## Pull requests

Keep changes focused. Explain user-visible behavior, safety/rollback impact, permissions, supported or experimental API status, tests run, hardware actually used, documentation changed, and any unverified manual path. A mock-tested or live-read capability must not be described as hardware-mutation verified.

Before requesting review, run `make verify` and `git diff --check`. If a required manual or hardware test was not run, state that directly. Do not treat the ad-hoc integrity signature in the local DMG as Developer ID signing or notarization.

All contributions are licensed under the repository's [MIT License](LICENSE). By participating, you agree to [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
