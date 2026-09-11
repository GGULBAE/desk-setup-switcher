# Desk Setup Switcher

A local-only macOS menu-bar app for saving desk setups and applying them deliberately.

Save available values from seven display and sound setting kinds as a profile, review the exact plan, then choose what to apply. Desk Setup Switcher does not switch profiles automatically.

> [!IMPORTANT]
> **Public beta in preparation:** there is no supported public download yet. The first supported build is planned as a free, Developer ID-unsigned DMG on [GitHub Releases](https://github.com/GGULBAE/desk-setup-switcher/releases) after the [public-beta completion gates](docs/COMPLETION-CRITERIA.md) pass. It will require a one-time **Open Anyway** decision on macOS. Local builds and ordinary CI artifacts are unsupported.

[English user guide](docs/guides/USER-GUIDE.md) · [한국어 사용자 가이드](docs/guides/USER-GUIDE.ko.md) · [Support matrix](docs/SUPPORT-MATRIX.md)

## Current profile scope

| Area | Saved values |
| --- | --- |
| Display | Main display, resolution |
| Sound output | Device, volume, mute |
| Sound input | Device, volume |

That is the complete current scope: seven setting kinds across **Display** and **Sound**. Network, automatic switching, per-setting inclusion switches, editable refresh rate, mirroring, and ColorSync profiles are not current features. Dormant legacy fields can round-trip for compatibility but never reach Apply.

## How it works

1. **Capture** reads the current Display and Sound values into a local profile. It changes nothing.
2. **Edit** names the profile and changes any available values in the seven-setting scope. Missing values remain absent.
3. **Review & Apply** shows proposed changes and omissions. Nothing changes until you explicitly choose **Apply Profile** or **Apply Available Settings**.

![Synthetic empty state with Capture Current Settings as the primary action](site/public/screenshots/capture.png)

The screenshot uses synthetic data and is not evidence of live hardware mutation. See the [asset provenance record](docs/RELEASE-ASSET-PROVENANCE.md).

## Safety and privacy

- Profiles, backups, and diagnostics stay on the Mac. There is no account, cloud sync, app-owned server, telemetry, analytics, advertising, or automatic profile switching.
- Capture is read-only. Apply always starts with an explicit review and confirmation.
- The app reads current state again immediately before execution. If the plan has changed, it applies nothing and returns to an updated review.
- Protected display changes use a 15-second **Keep Changes / Revert Now** window. Rollback is attempted when required, but is not presented as a guarantee.
- Results distinguish applied, skipped, failed, rolled-back, rollback-failed, and unverified outcomes.
- Selecting an audio input device does not record audio and does not require microphone access.

Exports may contain device labels and stable identifiers. Review them before sharing. Read the [privacy policy](docs/PRIVACY.md) for the complete data boundary.

## Project status

- Target: Apple Silicon on macOS 14 Sonoma. Exact release-candidate lifecycle evidence is still required before this becomes a supported public claim.
- Capture and source-group discovery have read-only hardware evidence. Apply and rollback currently have deterministic mock evidence only; no live hardware mutation is claimed as verified.
- The latest tray-activation change has deterministic coverage and passed the full non-live gate. Installed inactive-to-active appearance, focus timing, and keyboard behavior still need manual verification. See the [tray activation record](docs/TRAY-ACTIVATION-2026-09-11.md).
- The repository remains in a public-release holding state. See the [completion ledger](docs/COMPLETION-CRITERIA.md) and [distribution guide](docs/DISTRIBUTION.md).

## Installation

There is no supported release to install today. When this README links a supported versioned release:

1. Download its `-unsigned.dmg` and checksum from [GitHub Releases](https://github.com/GGULBAE/desk-setup-switcher/releases).
2. Verify the SHA-256 checksum, open the DMG, and move the app to **Applications**.
3. Try to open it once, then use **System Settings → Privacy & Security → Open Anyway** after verifying the source and checksum. Do not disable Gatekeeper globally.
4. Start with a small profile and inspect both the preview and itemized result.

## Build from source

Contributors need full Xcode and a Swift 6.1-or-later toolchain.

```sh
git clone https://github.com/GGULBAE/desk-setup-switcher.git
cd desk-setup-switcher
make verify
```

`make verify` is the canonical non-live gate. It does not mutate display, audio, network, mouse, or keyboard settings. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## Documentation

- **Use the app:** [English guide](docs/guides/USER-GUIDE.md) · [한국어 가이드](docs/guides/USER-GUIDE.ko.md) · [Support](SUPPORT.md)
- **Understand the boundaries:** [Privacy](docs/PRIVACY.md) · [Support matrix](docs/SUPPORT-MATRIX.md) · [Product scope](docs/PRODUCT.md)
- **Build or integrate:** [Profile JSON schema](docs/PROFILE-SCHEMA.md) · [Architecture](docs/ARCHITECTURE.md) · [Adapter contract](docs/ADAPTER-CONTRACT.md)
- **Prepare a release:** [Distribution gates](docs/DISTRIBUTION.md) · [External-beta report contract](docs/EXTERNAL-BETA-REPORT-TEMPLATE.md) · [Completion ledger](docs/COMPLETION-CRITERIA.md)

## Contributing, support, and security

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Use [SUPPORT.md](SUPPORT.md) for questions and ordinary bug reports. For vulnerabilities, unsafe mutations, privacy leaks, exposed secrets, or rollback failures, follow [SECURITY.md](SECURITY.md). Do not put sensitive details in a public issue.

Desk Setup Switcher is available under the [MIT License](LICENSE).
