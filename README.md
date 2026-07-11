# Desk Setup Switcher

> **Pre-release 0.1.0 implementation candidate:** the native app, safe profile core, concrete macOS adapters, editor/apply UI, and no-Developer-ID packaging pipeline are implemented. Final local `make verify`, the 158-test inventory, all five opt-in read-only discovery gates, universal DMG/checksum verification, and a fresh `/Applications` smoke test pass. There is no published release or GitHub CI result yet; live setting mutations, physical Intel, a live Keychain write, the downloaded/quarantined Gatekeeper path, and several manual workflows remain unverified.

Desk Setup Switcher is a free and open-source macOS menu-bar app for manually saving and applying display, audio, network, mouse, and keyboard profiles. It is local-first: no account, server, cloud sync, telemetry, analytics, or automatic profile switching.

## What is implemented

- A native SwiftUI `MenuBarExtra` app with `LSUIElement`, Settings, profile capture, editing, ordering, import/export, readiness, normal/force previews, itemized results, and a 15-second display confirmation flow.
- Versioned profile JSON, semantic/resource validation, safe actionable validation errors, migration scaffolding, permission-restricted Application Support persistence, last-known-good backup, corruption quarantine, and exclusive-create export.
- A capability-driven adapter contract and transaction engine with deterministic ordering, no-op filtering, pre-execution state/rollback revalidation, one active transaction, reverse rollback after fatal failure, and protected high-risk rollback tokens.
- Read-only display, audio, network, input, USB/hardware, and authorized-location discovery using macOS frameworks.
- Concrete display, audio, network, and input apply adapters. Display changes begin app-only and are promoted to the login session only after confirmation; Wi-Fi switching requires saved target and rollback preflight and treats an unreadable powered-on SSID as ambiguous. These mutation paths are mock verified only; ordinary tests and CI never change host settings.
- Local diagnostic redaction and rotating JSONL storage with sanitized snapshot/apply/storage/login/safety events and Settings browsing, refresh, and confirmed clearing. Diagnostic export is not implemented.
- A deterministic checked-in Xcode project generator, Swift Package targets, build/test/lint/analyze/package scripts, and GitHub Actions definitions.

The authoritative scope is [docs/PRODUCT.md](docs/PRODUCT.md). Architecture and safety boundaries are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/TECHNICAL-SPEC.md](docs/TECHNICAL-SPEC.md).

## Verification status

Evidence is intentionally split by confidence level:

| Evidence | Current result |
| --- | --- |
| Full local gate | Final `make verify` passed on 2026-07-11: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Xcode Analyze, packaging, checksum, and mounted-DMG checks |
| Default test behavior | Six opt-in cases skip by default: five read-only hardware cases and one Keychain-write round trip |
| Live read-only discovery | Display, audio, network, input, and readiness-context smoke tests passed on an Apple M5 Mac running macOS 26.5.2 |
| Universal package | The final no-Developer-ID DMG verified `arm64 x86_64`, bundle metadata, icon, English/Korean resources, `/Applications` link, ad-hoc app signature, and SHA-256 `3f99ebcea13ea1495e9c2471a45f66dacb851e3ba6670ce16aa84f48b26b99b7` |
| Manual packaged app | A fresh copy from the final DMG to `/Applications` launched background-only/menu-bar-only; the Korean popover, Settings, and an accessibility label passed inspection |
| Snapshot profile | The fresh install created one schema-v1 **Ready** profile from a read-only snapshot with all four setting groups; because it was a zero-operation plan, both Apply and Force Apply were disabled |
| Login item | Default-on `SMAppService` registration succeeded and Background Task Management reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out, leaving only disabled BTM history |
| Live mutations | **Not run** for display, audio, network, mouse, or keyboard |
| Live Keychain write | **Not run**; the Keychain path is mock verified |
| Remaining manual checks | Approval-required and failure/retry login-item states, actual login-at-boot after a reboot, full VoiceOver/keyboard/contrast, import/export, permission denial, Gatekeeper/quarantine, physical Intel, and mutation/rollback procedures are pending |
| CI and release | Workflow files exist, but no implementation commit has been pushed through Actions and no release has been published |

See the [support matrix](docs/SUPPORT-MATRIX.md) and [completion ledger](docs/COMPLETION-CRITERIA.md) for capability-level evidence and explicit manual procedures.

## Platform and limits

- macOS 14 Sonoma or later
- Native Swift/SwiftUI
- Universal `arm64` and `x86_64` build target; no physical Intel Mac has been tested
- Menu-bar-only accessory app with an `SMAppService` login-item preference
- Public macOS APIs for display, audio, and network operations
- Experimental labels for common input preferences backed by undocumented global preference keys
- Display rotation and activation mutation, administrative IPv4/DNS/proxy/service-order mutation, vendor configuration, UI scripting, and automatic switching are unsupported
- No-Developer-ID DMG baseline: the app has a free ad-hoc integrity signature, but no trusted publisher identity and no notarization
- MIT licensed

## Development

Use full Xcode with a Swift 6.1-or-later toolchain. The local reference environment is Xcode 26.6 with Swift 6.3.3. Scripts select `/Applications/Xcode.app` through a process-local `DEVELOPER_DIR` fallback when `xcode-select` points to Command Line Tools; they do not change global developer-directory state.

```sh
make build
make test
make lint
make analyze
make package
make verify-package
make verify
make clean
```

`make verify` is the primary gate: lint, tests, Debug/Release Swift and universal Xcode builds, Xcode Analyze, no-Developer-ID DMG creation, checksum validation, ad-hoc signature inspection, and mounted-DMG verification. It must not perform live discovery or a setting mutation.

The following gate opts into the repository's read-only hardware discovery tests. It still does not apply settings:

```sh
DESK_SETUP_LIVE_READ_TESTS=1 make test
```

Live mutation tests are not part of the ordinary suite or CI. Do not add or run one without an explicit environment gate, an interactive user action, a preflight snapshot, and a documented rollback path.

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## Privacy and security

Profiles, backups, and diagnostics are local. Exported profiles can contain user-selected device/network labels, network ranges, SSIDs, and exact latitude/longitude plus radius for location conditions; review or remove those values before sharing. They never contain Wi-Fi passwords. Saved-network association relies on credentials already managed by macOS; Keychain support is isolated and tested with synthetic data.

Read [docs/PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Packaging and distribution

`make package` creates `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg` and its `.sha256` file with a universal app and `/Applications` link. The “unsigned” filename means no Developer ID identity: the contained app is ad-hoc signed for code integrity and to meet the packaging design's signature prerequisite, but is not notarized. `make verify-package` checks the checksum, mounts the image read-only, and validates metadata, resources, both architectures, and signature class.

The final local artifact passes verification and its fresh `/Applications` install passed the smoke checks above, including default-on login-item registration and UI opt-out/re-enable. It is not published; quarantine/Gatekeeper, approval-required and retry states, and actual login-at-boot after a reboot remain untested. Developer ID signing and notarization are optional external release-operator work, not current project claims. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Project tracking

- [Roadmap](docs/ROADMAP.md)
- [Completion criteria](docs/COMPLETION-CRITERIA.md)
- [Support matrix](docs/SUPPORT-MATRIX.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE) © 2026 GGULBAE.
