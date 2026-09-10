# Desk Setup Switcher

A simple, local-only macOS menu-bar app for moving between desk setups without changing settings behind your back.

Save selected display and audio settings as a profile. When you want to use it, review the exact plan and decide what to apply.

> [!IMPORTANT]
> **Unreleased public beta:** there is no supported public download yet. The first supported build will be a free, Developer ID-unsigned DMG on [GitHub Releases](https://github.com/GGULBAE/desk-setup-switcher/releases) after the [public-beta completion gates](docs/COMPLETION-CRITERIA.md) pass. Its app carries an ad-hoc integrity signature but is not notarized, so macOS will require a one-time **Open Anyway** decision. Local and ordinary CI artifacts remain unsupported; do not redistribute them or create or push a `v*` tag.

[English user guide](docs/guides/USER-GUIDE.md) · [한국어 사용자 가이드](docs/guides/USER-GUIDE.ko.md) · [Support matrix](docs/SUPPORT-MATRIX.md)

## How it works

### 1. Capture

Choose **Capture Current Settings** from the menu-bar app. Capture reads the current Mac state and creates a profile for review; it does not change a setting.

![Synthetic empty-state screen with Capture Current Settings as the primary action](site/public/screenshots/capture.png)

### 2. Edit

Name the profile and choose **main display**, **resolution**, **output device/volume**, and **input device/volume**. These are the only captured and applied setting kinds; Network and Advanced are absent. Sound groups device and volume controls together in two sections: **Output** and **Input**. Registered values are always included; there are no per-setting inclusion labels or switches. Missing values are not invented. Retired setting kinds remain dormant for compatibility.

![Historical synthetic profile editor showing display settings and saved profiles](site/public/screenshots/edit.png)

The packaged public-surface image above predates the current seven-option scope; see the [current Sound grouping and verification note](docs/AUDIO-SECTIONS-2026-09-07.md).

### 3. Review, then apply

Choose **Apply** on a tray card to open its review, then inspect every proposed change and omission. Nothing changes until you explicitly choose **Apply Profile** or **Apply Available Settings**.

![Synthetic apply preview showing planned changes and the protected-change warning](site/public/screenshots/review.png)

The screenshots contain synthetic data from a non-mutating demo state. They show the intended product flow, not live hardware-mutation evidence. See the [asset provenance record](docs/RELEASE-ASSET-PROVENANCE.md) and [static demo-site source](site/README.md).

When a saved profile matches the current Mac, the menu-bar indicator shows its profile name on one horizontal line.
The App Information page keeps its four project links centered as one compact group, with aligned icon and text columns.

Profiles now capture, edit, and apply seven setting kinds: **main display**, **resolution**, **output device**, **output volume**, **output mute**, **input device**, and **input volume**. **Display** and **Sound** keep the stable numbered rail at normal widths; small windows and accessibility text use a segmented selector. All options are directly visible, with no Advanced or Network section. Sound uses two shared **Output/Input** cards, each containing its device picker and volume control; Output also shows **Output mute** (**소리 끔**). This switch changes the saved mute value, not whether the setting is included. Resolution selection preserves the current refresh rate; an unavailable resolution/rate combination is skipped instead of changing the rate. Legacy mirroring, ColorSync, network, and other retired setting kinds round-trip dormant and cannot reach Apply, including Force. Profile snapshots query only Display and Audio and no longer needs Location access. Profiles do not show Last application history. **App Settings** contains launch-at-login preferences and on-demand Diagnostics; registration details remain in **Login item details**. A three-profile tray now uses a content-sized viewport instead of the maximum-height bucket. Apply Preview leads with change/skip/review counts and compact before → after rows; omissions and validation stay in one disclosure unless they block Apply. The Beta warning, protected-change timer, refreshed-plan state, Escape behavior, and minimum-window scroll order remain explicit. These are deterministic synthetic/offscreen improvements only; installed accessibility, hardware mutation/rollback, and release-distribution evidence remain required.

The [minimal profile scope](docs/MINIMAL-PROFILE-SCOPE-2026-09-07.md) supersedes the earlier basic/Advanced correction and records the original six-option contract and verification boundary; the [output-mute follow-up](docs/OUTPUT-MUTE-2026-09-08.md) adds the seventh setting kind without restoring inclusion switches.

The [output-mute follow-up](docs/OUTPUT-MUTE-2026-09-08.md) restores **Output mute / 소리 끔** without inclusion switches. Full verification passed, and the user-authorized local reinstall/startup preserved profile values and auto-launch preferences; saved mute inclusion flags were normalized as documented. Live audio application and installed UI interaction remain unverified.

The [registered-values follow-up](docs/REGISTERED-PROFILE-VALUES-2026-09-08.md) removes per-setting inclusion labels and toggles. All saved values in the supported setting kinds participate in preflight, including previously excluded values; absent values remain absent, ambiguous main-display selection stays dormant until explicitly selected, and runtime availability still gates application. Full `make verify`, 19 synthetic Settings fixtures, and the existing tray matrix passed. The verified app was installed and relaunched with both profile files unchanged and the consented login preference retained.

The [compact tray-action follow-up](docs/TRAY-ACTIONS-2026-09-08.md) places **Apply / Edit / trash** on one row, removes the trash menu step, and leaves a blank caption line instead of passive matched/unavailable explanations. Profile readiness symbols/text, disabled actions, read-only Apply Preview, and inline deletion confirmation remain intact. Full `make verify` and 21 synthetic tray fixtures passed; the verified app was installed and launched with both profile files and the consented login preference preserved.

The [2026-09-08 spacing and login-request follow-up](docs/SPACING-LOGIN-2026-09-08.md) removes duplicate Display/Sound detail headings, adds sidebar-action and form-bottom insets, and measures one-to-three-profile tray content once before opening instead of relying on a fixed count bucket. Open-session geometry stays frozen and overflow remains scrollable. A saved launch-at-login ON preference no longer triggers registration on startup: enabling or retrying registration requires an explicit App Settings action. The app does not invoke `sfltool`. Full `make verify` and 40 synthetic UI fixtures passed; the verified local package was installed and launched with both profile files unchanged. Installed keyboard/VoiceOver, authorization prompts, and reboot behavior remain separate verification boundaries.

The [2026-09-10 tray clarity follow-up](docs/TRAY-CURRENT-PROFILE-2026-09-10.md) moves the current-state signal onto the matching profile card, removes the separate tray result card, adds an Apply icon, and removes the always-visible login-registration disclosure while retaining mismatch recovery actions.

The grouped Sound 2026-09-07 follow-up passed `make verify` on retry and the 19-fixture offscreen matrix, was reinstalled, and launched from `/Applications`. Both profile files remained byte-identical after startup; the old app and profile files are backed up. This is installation/startup evidence, not installed keyboard or hardware verification; see the [current verification and installation record](docs/AUDIO-SECTIONS-2026-09-07.md).

The requested installed keyboard/scroll follow-up is still unverified: the app process and executable identity were confirmed, but the native screen connection timed out before a usable accessibility tree or screenshot was available. No keyboard, scrolling, Save, or Apply action was attempted. See the [follow-up verification boundary](docs/AUDIO-SECTIONS-2026-09-07.md#installed-interaction-follow-up).

## Install

Supported binaries will be provided only through versioned GitHub Releases. There is no App Store release and the initial public beta does not require a paid Apple Developer Program membership. When this README identifies a release as supported:

1. Get the versioned `-unsigned.dmg` and checksum from the project’s [GitHub Releases page](https://github.com/GGULBAE/desk-setup-switcher/releases). Do not substitute an Actions artifact or third-party mirror.
2. Verify the SHA-256 checksum, open the DMG, and drag **Desk Setup Switcher** to **Applications**.
3. Try to open the app once. When macOS blocks the unidentified developer, open **System Settings → Privacy & Security**, choose **Open Anyway**, and confirm only after checking the release URL and checksum. The app appears in the menu bar rather than the Dock.
4. Start with a small profile and inspect both the preview and the itemized result.

Do not disable Gatekeeper globally, remove quarantine with `xattr`, or use an artifact whose checksum differs. The manual exception is expected only because this project currently uses the free unsigned distribution path.

## Privacy and safety

- Profiles, backups, and diagnostics stay on the Mac. There is no account, cloud sync, app-owned server, telemetry, analytics, ads, or automatic profile switching.
- Capture is read-only. Applying a profile always requires an explicit review and confirmation.
- The app reads current state again before execution. If the profile, device state, capability, or rollback evidence changed, it applies nothing and returns to an updated review.
- High-risk display and network changes use a 15-second **Keep Changes / Revert Now** window. A timeout, close, confirmation failure, or fatal transaction error requests rollback where supported.
- Rollback is an attempt, not a guarantee. Results distinguish applied, skipped, failed, rolled back, rollback-failed, and unverified outcomes so you can check the current macOS state directly.

Exports can contain device labels, SSIDs, network ranges, stable identifiers, and dormant legacy conditions. Review them before sharing. Profiles never contain Wi-Fi passwords. Read the [privacy policy](docs/PRIVACY.md) for the complete data boundary.

## Permissions and current limits

| Access | When it may be needed | If declined |
| --- | --- | --- |
| Location | macOS may require it to reveal the current Wi-Fi name during Capture | Capture continues without Wi-Fi; unrelated display, audio, and wired-network values remain available |
| macOS authorization | An included, service-specific IPv4 change may require protected SystemConfiguration access | The change is cancelled or reported as not applied |
| Launch at login | Only after you enable it in Settings | The app remains manual-launch only; this preference is off by default |

Selecting an audio input device does not record audio and does not require microphone access.

The planned initial public beta targets Apple Silicon and macOS 14 Sonoma, but exact-candidate Sonoma lifecycle evidence is still required before that becomes a support claim. The project builds an `x86_64` slice, but physical Intel installation and runtime testing have not passed, so Intel is not supported. The public DMG will be Developer ID-unsigned and not notarized; that packaging status is a deliberate cost-free distribution choice, not an Apple trust claim. Current user-facing profile work is limited to the seven Display/Sound setting kinds; no live setting mutation or hardware rollback is claimed as verified. See the [support matrix](docs/SUPPORT-MATRIX.md) for capability-level evidence.

## Build from source

Contributors need full Xcode and a Swift 6.1-or-later toolchain.

```sh
git clone https://github.com/GGULBAE/desk-setup-switcher.git
cd desk-setup-switcher
make verify
```

`make verify` is the canonical local gate. Release JSON evidence rejects decoded-equivalent duplicate keys with parser-independent scanning so local and CI Ruby versions enforce the same rule. Pull-request CI runs the app gate against GitHub's merge preview, then audits public Git history from a separate full-history checkout of the exact PR head so GitHub's temporary merge-commit identity is not mistaken for publishable repository history. Its packaged DMG uses the same no-Developer-ID packaging class planned for the public beta, but a local build is not supported unless its exact bytes and checksum are attached to the approved versioned GitHub Release. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow. Release engineering and remaining evidence are tracked in the [distribution guide](docs/DISTRIBUTION.md) and [completion ledger](docs/COMPLETION-CRITERIA.md).

The [2026-09-08 site dependency refresh](docs/SITE-DEPENDENCY-REFRESH-2026-09-08.md) updates the pinned Vinext/RSC tooling and vulnerable transitive packages. A clean install reports zero registry advisories, and public-site verification covers the new chunk layout and unchanged privacy/publication boundaries. Vinext still vendors the unpatched image parser for build-time use; a deployment-output regression rejects that parser in client/Worker chunks. This does not mean the parser itself was patched or the site was deployed. The accompanying [CI compatibility follow-up](docs/CI-COMPATIBILITY-2026-09-08.md) reviews exact synthetic-fixture audit exceptions and measures actual offscreen control bounds and label-relative ink contrast instead of assuming one macOS release's native control sizes or disabled-text colors.

## Documentation

- **Use the app:** [English guide](docs/guides/USER-GUIDE.md) · [한국어 가이드](docs/guides/USER-GUIDE.ko.md) · [Support](SUPPORT.md)
- **Understand the boundaries:** [Privacy](docs/PRIVACY.md) · [Support matrix](docs/SUPPORT-MATRIX.md) · [Product scope](docs/PRODUCT.md)
- **Build or integrate:** [Profile JSON schema](docs/PROFILE-SCHEMA.md) · [Architecture](docs/ARCHITECTURE.md) · [Adapter contract](docs/ADAPTER-CONTRACT.md)
- **Prepare a release:** [Distribution gates](docs/DISTRIBUTION.md) · [External-beta v3 contract](docs/EXTERNAL-BETA-REPORT-TEMPLATE.md) · [Completion ledger](docs/COMPLETION-CRITERIA.md)

## Contributing, support, and security

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md). Keep changes inside the project’s local-only, explicit-apply safety model.

Use [SUPPORT.md](SUPPORT.md) for questions and ordinary bug reports. For vulnerabilities, unsafe mutations, privacy leaks, exposed secrets, or rollback failures, follow [SECURITY.md](SECURITY.md). Private vulnerability reporting is currently disabled: request a private channel without putting sensitive details in the initial contact, and never report a vulnerability in a public issue.

Desk Setup Switcher is available under the [MIT License](LICENSE).
