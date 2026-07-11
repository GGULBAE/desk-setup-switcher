# Contributing

Thanks for helping build Desk Setup Switcher. The project is pre-alpha and prioritizes safety, privacy, testability, and honest capability reporting.

## Before starting

1. Read [docs/PRODUCT.md](docs/PRODUCT.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and [AGENTS.md](AGENTS.md).
2. Check [docs/ROADMAP.md](docs/ROADMAP.md) and existing issues.
3. Discuss changes that expand scope, add a permission, use a non-public contract, or alter distribution/privacy behavior.

## Development expectations

- Use Swift/SwiftUI and the checked-in Apple-framework adapter boundaries.
- Do not introduce a runtime dependency on Homebrew or another CLI.
- Do not add application-owned outbound network traffic, telemetry, accounts, or cloud storage.
- Keep CI and ordinary local tests free of live system-setting mutations.
- Add tests for success, capability limitation, permission denial, partial failure, fatal failure, and rollback where relevant.
- Use synthetic device/network data in tests and screenshots.
- Update documentation and the evidence ledger with behavior changes.

Canonical build and verification commands will be added with Milestone 1. Until then, do not infer implementation status from this documentation-only baseline.

## Pull requests

Keep changes focused. Explain the user-visible behavior, safety/rollback impact, permissions, public or experimental API status, tests run, hardware actually used, and documentation changed. A mock-tested capability must not be described as hardware verified.

All contributions are licensed under the repository's [MIT License](LICENSE). By participating, you agree to [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
