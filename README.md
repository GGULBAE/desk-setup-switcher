# Desk Setup Switcher

> **Pre-release 0.1.0 implementation candidate:** the native app, safe profile core, concrete macOS adapters, protected profile-editing UI, and no-Developer-ID packaging pipeline are implemented. The current header/editor follow-up passes full local `make verify` with 215 non-live tests and a verified universal package; UI-hardening commit `5f0cabc` remains the latest matching GitHub Actions baseline. The earlier repair baseline retains its 2026-07-11 live-read and fresh-install evidence. No release is published, and live setting mutations, physical Intel, a live Keychain write, the downloaded/quarantined Gatekeeper path, and several manual workflows remain unverified.

Desk Setup Switcher is a free and open-source macOS menu-bar app for manually saving and applying display, audio, network, mouse, and keyboard profiles. It is local-first: no account, server, cloud sync, telemetry, analytics, or automatic profile switching.

## What is implemented

- A native SwiftUI `MenuBarExtra` app with `LSUIElement`, Settings, profile capture, editing, ordering, import/export, readiness, normal/force previews, itemized results, and a 15-second display confirmation flow.
- App-lifetime profile drafts with save/discard/cancel protection across selection, replacement, and ordinary quit paths. `⌘S` saves a valid dirty draft, fixed save/revert controls remain outside the editor scroll area, and current-settings capture updates only the reviewable draft until the user saves.
- The popover header provides a compact Capture action plus icon-only, accessibility-labelled Settings and Quit actions. Each profile keeps one primary Apply action and direct Edit action; ellipsis, availability-review, available-items, and manual-refresh controls are not exposed. Capture success appears for about three seconds only after a successful capture.
- Enabling a display, audio, network, or input group immediately reveals its per-option controls; enabling an option reveals its concrete value editor. Disabling a group or option preserves its configured value. Legacy or imported conditions remain persisted and evaluated, but condition editing is no longer exposed in Settings.
- Value-first profile summaries and apply previews keep technical identifiers behind disclosures, preserve imported symbols through a curated icon picker, explain disabled actions with text, and retain accessible keyboard/value metadata.
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
| Current header/editor full gate | `make verify` passed on 2026-07-12: localization/policy lint, 215 tests (112 XCTest + 103 Swift Testing), Swift and universal Xcode Debug/Release, Analyze, DMG creation, checksum, mounted-image resources, architectures, and ad-hoc signature classification. The 56 presentation-specific tests comprise 29 draft and 27 presentation/condition cases |
| Current local universal package | The no-Developer-ID DMG verified `arm64 x86_64`, bundle metadata, icon, English/Korean resources, `/Applications` link, ad-hoc app signature, and SHA-256 `45772d20e6d7655c41ed4ff5d0261257b98f1361f4cf8cc38ebf837720d5820b` |
| Historical full local gate | Repair baseline `4e45328` passed `make verify` on 2026-07-11: lint/policy, 158 tests (83 XCTest + 75 Swift Testing), Swift/Xcode Debug and Release, Xcode Analyze, packaging, checksum, and mounted-DMG checks |
| Default test behavior | Six opt-in cases skip by default: five read-only hardware cases and one Keychain-write round trip |
| Historical live read-only discovery | On 2026-07-11, display, audio, network, input, and readiness-context smoke tests passed on an Apple M5 Mac running macOS 26.5.2; they were not rerun for the current UI tree |
| Historical local universal package | The 2026-07-11 post-fix no-Developer-ID DMG verified `arm64 x86_64`, bundle metadata, icon, English/Korean resources, `/Applications` link, ad-hoc app signature, and SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f` |
| Historical CI universal package | [Actions run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) uploaded unsigned artifact ID `8249295840`; its downloaded checksum file verified CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. Local and CI DMGs are not byte-for-byte reproducible |
| Historical manual packaged app | The 2026-07-11 local-DMG copy launched from `/Applications` as background-only/menu-bar-only; the Korean popover, Settings, and one accessibility label passed inspection. This does not verify the current UI tree |
| Historical snapshot profile | That fresh install created one schema-v1 **Ready** profile from a read-only snapshot with all four setting groups; because it was a zero-operation plan, both Apply and Force Apply were disabled |
| Historical login item | Default-on `SMAppService` registration succeeded and Background Task Management reported `[enabled, allowed, notified]`; UI opt-out disabled it and re-enable restored enabled status. Final cleanup opted out, leaving only disabled BTM history |
| Live mutations | **Not run** for display, audio, network, mouse, or keyboard |
| Live Keychain write | **Not run**; the Keychain path is mock verified |
| Remaining manual checks | No current-tree screenshot walkthrough or full VoiceOver/keyboard/focus/contrast/text-size audit was run. Approval-required and failure/retry login-item states, actual login-at-boot after a reboot, import/export, TCC permission denial/grant, Gatekeeper/quarantine, physical Intel, and mutation/rollback procedures are pending |
| Latest CI universal package | UI-hardening commit `5f0cabc` passed [Actions run `29181900967`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29181900967): full `make verify` and unsigned artifact ID `8256718472` upload succeeded. The downloaded checksum file verified CI DMG SHA-256 `f3d82b033e8e375c9063a9b72cbd174d94a03f0cdd4414961895db3b3dcfc3f4`; this predates the local header/editor follow-up. No release is published |

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

`make lint` also validates English/Korean key parity, duplicate keys, format-placeholder compatibility, and statically discoverable localized UI keys. Passing this structural check is not a rendered bilingual walkthrough or a linguistic-quality audit.

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

The current UI tree produced and verified the replacement universal package and checksum above, but it has not been installed or smoke-tested. The 2026-07-11 baseline artifact retains the recorded fresh `/Applications` checks, including default-on login-item registration and UI opt-out/re-enable. Nothing is published; quarantine/Gatekeeper, approval-required and retry states, and actual login-at-boot after a reboot remain untested. Developer ID signing and notarization are optional external release-operator work, not current project claims. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Project tracking

- [Active UI refinement goal](docs/UI-REFINEMENT-GOAL.md)
- [Roadmap](docs/ROADMAP.md)
- [Completion criteria](docs/COMPLETION-CRITERIA.md)
- [Support matrix](docs/SUPPORT-MATRIX.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE) © 2026 GGULBAE.
