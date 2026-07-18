# Desk Setup Switcher

Desk Setup Switcher is a local-only macOS menu-bar app for saving selected display, audio, and network settings as profiles. Capture what is connected, keep only the settings you want, review the exact plan, and apply it only when you choose.

> **Release status:** there is no supported public download yet. Contributor builds and ordinary CI produce development-only, ad-hoc-signed artifacts. A [read-only remote-controls audit](docs/REMOTE-RELEASE-CONTROLS-AUDIT-2026-07-18.md) confirmed that the effective default-branch workflow starts for every `v*` tag and can auto-publish the unsigned `v0.1.0` artifact after its version guard. Ordinary `make verify` runs deterministic offline/mocked remote-controls tests only; the explicit `make verify-remote-controls` final-pre-tag command performs authenticated read-only GitHub GETs after its complete policy is configured. That checked-in policy is intentionally `configured:false` today, so the command stops before network access. The release-only signed-candidate path is not operational until its protected environment, credentials, repository protections, and credentialed verification are configured and recorded. Do not create a `v*` tag before the [completion ledger](docs/COMPLETION-CRITERIA.md) closes that gate. The first supported download will be a signed and notarized DMG published on [GitHub Releases](https://github.com/GGULBAE/desk-setup-switcher/releases) after every public-beta gate passes.

[English user guide](docs/guides/USER-GUIDE.md) · [한국어 사용자 가이드](docs/guides/USER-GUIDE.ko.md) · [Support matrix](docs/SUPPORT-MATRIX.md)

## Capture → Edit → Review & Apply

### 1. Capture

Open the menu-bar item and choose **Capture Current Settings**. Capture reads the Mac and creates a profile for review; it does not change a setting.

![Synthetic empty-state screen with Capture Current Settings as the primary action](site/public/screenshots/capture.png)

### 2. Edit

Name the profile and include only the display, audio, and network values that should change with it. Unsupported or unavailable values are not presented as safe, runnable choices.

![Synthetic profile editor showing display settings and saved profiles](site/public/screenshots/edit.png)

### 3. Review & Apply

Inspect every proposed change and omission. Nothing changes until you explicitly choose **Apply Profile** or **Apply Available Settings**.

![Synthetic apply preview showing planned changes and the protected-change warning](site/public/screenshots/review.png)

These screenshots use synthetic data and a non-mutating demo state. They show the intended product flow, not live hardware-mutation evidence. The [static demo-site source](site/README.md) is available in the repository but is not a public download channel.

## One-minute quick start

### After the supported release exists

1. Download the signed, notarized DMG and checksum from the project’s [GitHub Releases page](https://github.com/GGULBAE/desk-setup-switcher/releases).
2. Verify the checksum, drag **Desk Setup Switcher** to **Applications**, and launch it. The app appears in the menu bar rather than the Dock.
3. Use **Capture → Edit → Review & Apply**. Start with a small profile and inspect the itemized result after Apply.

If macOS cannot verify an official release, stop and report it. Do not bypass Gatekeeper for an end-user installation.

### Contributor build

Contributors need full Xcode and a Swift 6.1-or-later toolchain. The canonical local gate is:

```sh
make verify
```

Its DMG is an ad-hoc-signed development artifact, not a supported download, and must not be presented as an official release. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [distribution policy](docs/DISTRIBUTION.md) for the future signed release path.

## Privacy and safety

- Profiles, backups, and diagnostics stay on the Mac. The app has no account, cloud sync, app-owned server, telemetry, analytics, ads, or automatic profile switching.
- Capture is read-only. Applying a profile always requires an explicit review and confirmation.
- The app reads current state again before execution. If the profile, device state, capability, or rollback evidence changed, it applies nothing and returns to a refreshed review.
- High-risk display and network changes use a 15-second **Keep Changes / Revert Now** safety window. Timeout, window close, confirmation failure, or a fatal transaction error requests rollback where supported.
- Rollback is an attempt, not a guarantee. The result distinguishes success, failure, omission, rollback, rollback failure, and unverified outcomes so the current macOS state can be checked directly.

Exports can contain device labels, SSIDs, network ranges, stable identifiers, and dormant legacy location conditions. Dormant or snapshot-only values can remain in JSON with inclusion off. Review them before sharing. Profiles do not contain Wi-Fi passwords. Read the [privacy policy](docs/PRIVACY.md) for the full data boundary.

## Minimum permissions

| Access | When it may be needed | If declined |
| --- | --- | --- |
| Location | macOS may require it to reveal the current Wi-Fi name during Capture | Capture without Wi-Fi; unrelated display, audio, and wired-network values remain available |
| macOS authorization | Applying an included, service-specific IPv4 change can require protected SystemConfiguration access | The change is cancelled or reported as not applied |
| Launch at login | Only after the user enables it in Settings | The app remains manual-launch only; this preference is off by default |

Selecting an audio input device does not record audio, so the app does not need microphone access for that operation.

## Supported scope and honest limits

- The planned initial public beta targets **Apple Silicon** on **macOS 14 Sonoma or later**.
- The project can build an `x86_64` slice, but physical Intel installation and runtime testing have not passed. Intel is not currently a supported platform.
- Read-only discovery has live Apple Silicon evidence. Display, audio, and network apply/rollback paths are deterministic mock verified; no live hardware-mutation verification is claimed.
- Current user-facing profile work is limited to Display, Audio, and Network. Legacy Input and condition data may round-trip through profile files but is dormant and does not drive automatic switching.
- Keyboard behavior, accessible names and values, and non-color state cues remain part of UI quality. Comprehensive assistive-technology certification is outside the initial beta scope.

Capability-level evidence and unresolved hardware/manual checks live in the [support matrix](docs/SUPPORT-MATRIX.md).

## Documentation

- [English user guide](docs/guides/USER-GUIDE.md) and [한국어 사용자 가이드](docs/guides/USER-GUIDE.ko.md)
- [Profile JSON schema and interchange guide](docs/PROFILE-SCHEMA.md)
- [Adapter contract and transaction safety](docs/ADAPTER-CONTRACT.md)
- [Product scope](docs/PRODUCT.md) and [architecture](docs/ARCHITECTURE.md)
- [Distribution and release gates](docs/DISTRIBUTION.md)
- [Detailed release-baseline audit](docs/OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md), [remote release-controls audit](docs/REMOTE-RELEASE-CONTROLS-AUDIT-2026-07-18.md), and [completion ledger](docs/COMPLETION-CRITERIA.md)

## Contributing, support, and security

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), follow the [Code of Conduct](CODE_OF_CONDUCT.md), and keep changes inside the project’s local-only, explicit-apply safety model.

Use [SUPPORT.md](SUPPORT.md) for questions and bug reports. For vulnerabilities, unsafe mutations, privacy leaks, exposed secrets, or rollback failures, follow the current [SECURITY.md](SECURITY.md) instructions. Private vulnerability reporting is currently disabled: request a private channel without including sensitive details in the initial contact, and never use a public issue.

Desk Setup Switcher is available under the [MIT License](LICENSE).
