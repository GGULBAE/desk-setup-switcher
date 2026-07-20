# Desk Setup Switcher user guide

[한국어](USER-GUIDE.ko.md) · [Guide index](README.md)

Desk Setup Switcher saves selected display, audio, and network settings as local profiles. Nothing is applied automatically. The normal flow is **Capture → Edit → Review & Apply**.

## Before you install

There is no supported public download yet. Repository and CI-generated DMGs are ad-hoc-signed development evidence; they are not signed, notarized end-user releases. Do not bypass Gatekeeper to install them as an ordinary user.

After `v0.1.0` is approved and published, the canonical download will be the project's [GitHub Releases page](https://github.com/GGULBAE/desk-setup-switcher/releases). The planned initial public-beta target is:

- Apple Silicon;
- a macOS 14 Sonoma deployment target, after the exact candidate passes the Sonoma lifecycle gate; and
- the signed and notarized DMG attached to the published GitHub Release.

The included Intel slice is not an Intel support claim. Physical Intel installation and runtime testing have not passed. There is also no App Store release, in-app updater, or supported Homebrew installation yet.

On 2026-07-20, current-source opt-in read-only tests passed the Display, Audio, Network, Input, ConditionContext, and ApplyLivePreparation group/base paths on Apple Silicon/macOS 26.5.2. Those tests did not itemize actual ColorSync-profile, input-volume, or service-IPv4 field presence/read on this host, so those item-level live-read claims and every Display, Audio, and Network apply/rollback path remain mock-only. No live setting mutation is verified. Read the [support matrix](../SUPPORT-MATRIX.md) before relying on a capability. This guide must not be read as hardware certification.

Keyboard behavior, accessibility names and values, and non-color state cues are maintained. Comprehensive assistive-technology certification is outside the initial beta scope.

## Install after the official release

1. Open the published GitHub Release and confirm that its notes identify it as the approved public beta, not an unsigned candidate, discontinued release, or affected release. A public beta may still carry GitHub's **Pre-release** badge.
2. Download the DMG and its published checksum from that same release. Confirm the SHA-256 matches the release record.
3. Open the DMG, drag **Desk Setup Switcher** to **Applications**, and eject the DMG.
4. Open the app from **Applications**. A normal first-open confirmation for an Internet download is expected. If macOS says the developer cannot be verified, the app cannot be checked, or the artifact is damaged, stop. Do not use **Open Anyway** for an official release; verify the download and report the problem.
5. Look for the Desk Setup Switcher icon in the menu bar. The app is menu-bar-only, so it does not normally show a Dock icon or a main window at launch.

**Launch at login is off by default.** Enable it only if wanted in **Settings → System → Login**. The app shows the requested setting and macOS registration status separately because macOS may require approval.

## One-minute workflow

1. **Capture:** Open the menu-bar item and choose **Capture Current Settings**. Capture reads the Mac and creates a new reviewable profile; it does not apply a change.
2. **Edit:** Choose **Edit Profile**, name the profile, select only the settings you want under **Display**, **Audio**, and **Network**, then save.
3. **Review & Apply:** Choose **Review…** or **Review Available…**. Check every change and omission. Nothing changes until you explicitly choose **Apply Profile** or **Apply Available Settings**.

There is no timer, condition, or background rule that applies a profile automatically.

## 1. Capture

Open the menu-bar item and choose **Capture Current Settings**. On an empty first run, this is the single main action in the body. When profiles already exist, Capture is in the header.

Capture records readable snapshot values in the local profile for format compatibility. The editor presents a value as runnable only when the current app can carry it through capture, validation, planning, apply, verification, and rollback. Unsupported or unreadable values do not become runnable; dormant or snapshot-only values can remain stored with inclusion off and can therefore appear in exported JSON.

macOS may require Location access to reveal the current Wi-Fi network name. The app explains this before requesting permission. You can:

- choose **Allow Location and Capture**;
- choose **Capture Without Wi-Fi**; or
- open macOS System Settings and return to Capture afterward.

Declining Location does not block unrelated display, audio, or wired-network values. The permission is used only so macOS can disclose the current Wi-Fi name; Desk Setup Switcher does not request coordinates or upload location data.

## 2. Edit

Choose **Edit Profile** on a profile to open **Settings → Profiles**.

- Give the profile a recognizable name and icon.
- For each visible setting, use **Apply with profile** to choose whether it belongs to this profile. **Included** and **Not included** are shown with text and a symbol, not color alone.
- Configure only the values you intend to change. The current editor exposes supported display mode/primary-display/ColorSync choices, audio defaults and settable volumes, and exact Ethernet or Wi-Fi service DHCP/manual IPv4 where the current capability catalog allows them.
- Save the profile. `⌘S` saves a valid dirty draft.

An unavailable saved target remains visible with a warning when possible. Reconnect the device or turn **Apply with profile** off for that row before saving. Do not infer support from a value that is absent: the app hides choices that cannot complete its capture/apply/verify/rollback contract on the current snapshot.

If you switch profiles, import, apply, or quit with unsaved changes, the app asks you to save, discard, or cancel. A failed save keeps the draft intact. Capture creates a separate profile and does not silently replace an open draft.

## 3. Review & Apply

Each profile exposes one state-aware review action:

- **Review…** means all included applicable settings can be prepared.
- **Review Available…** means some executable settings exist but other items will be omitted, blocked, unsupported, or unavailable.

The review is read-only. Inspect the target values, operation list, omissions, and technical details before continuing.

- **Apply Profile** starts a complete plan.
- **Apply Available Settings** applies only the listed executable items. Use it only when every omission is expected.
- If the Mac changes after the review opens, the app applies nothing and presents a refreshed review. Review it again.
- A no-op profile has nothing to change and cannot be applied.

After execution, inspect the itemized result. An item can be succeeded, failed, skipped, unsupported, rolled back, rollback failed, or not verified. A success label requires read-back; if read-back is unavailable or the change still appears necessary, the item is **not verified**.

### Protected changes and rollback

High-risk display and network changes remain temporary while a 15-second safety window is open.

- Choose **Keep Changes** only when the Mac is usable and the result matches the review.
- Choose **Revert Now** if the display, network, or result is unexpected.
- Closing the safety window, quitting the app, or allowing the timer to expire requests restoration of the previous configuration.

On a fatal failure, the transaction engine attempts supported completed steps in reverse order. Rollback is capability-specific and can itself fail; it is not a substitute for checking the itemized result and the current macOS settings. If a protected change or rollback behaves unsafely, restore the original value in macOS System Settings when possible and follow the current [SECURITY.md](../../SECURITY.md) instructions. Private vulnerability reporting is currently disabled; request a private channel without putting sensitive details in the initial contact or a public issue.

## Permissions and privacy

Desk Setup Switcher is local-only. It has no account, cloud sync, app-owned server, telemetry, analytics, ads, or automatic profile switching.

| Access | Why it may appear | If declined |
| --- | --- | --- |
| Location | macOS can require it to reveal the current Wi-Fi name during Capture | Capture without Wi-Fi; unrelated capabilities continue |
| macOS authorization for a protected network change | An included service-specific IPv4 change can require authorized SystemConfiguration access | Cancel or denial leaves the item failed/not applied |
| Microphone | Not used; choosing an audio input device does not record audio | No microphone permission should be needed |

Profiles and diagnostics stay under `~/Library/Application Support/Desk Setup Switcher/`. Imports are read from, and exports are written to, locations you select. The app does not store Wi-Fi passwords in profiles or logs; saved-network credentials remain managed by macOS.

See the [privacy policy](../PRIVACY.md) for the full local-data boundary.

## Import and export

Open **Settings → Profiles**, then open **More Profile Actions**.

### Export

1. Save any draft you want included.
2. Choose **Export Saved Profiles…**.
3. Choose a new local `.json` destination.

Export includes all saved profiles, not the current unsaved draft, and does not overwrite an existing destination. The JSON contains no passwords, but it can contain profile/device labels, SSIDs, network ranges, stable device identifiers, and exact legacy location conditions. Dormant or snapshot-only values can remain with inclusion off. Review and redact the file before sharing.

### Import

1. Choose **Import…** and select one local `.json` profile document.
2. Read the validation result and replacement count.
3. Confirm only if you intend to replace **all** local profiles. The app keeps a last-known-good backup.

Import is replacement, not merge. The app rejects invalid, oversized, unsafe, unsupported-newer-schema, and duplicate-ID documents before committing them. Older schema data may be migrated, but imported legacy conditions remain dormant and do not trigger or block the manual workflow. The format is for app interchange and recovery, not a stable automation API; see [Compatibility and versioning](../COMPATIBILITY.md).

## Diagnostics and support

For a Capture, readiness, storage, or Apply problem:

1. Open **Settings → System → Open Advanced Diagnostics…**.
2. Choose **Refresh** for recent redacted events. **Refresh Readiness** performs a read-only update of current facts.
3. Review the last result, last snapshot, readiness facts, and item-level status.
4. Choose **Clear Events…** to delete only the app's rotated diagnostic event files.

Diagnostics are local and no diagnostic is uploaded automatically. Diagnostic export is not implemented. Although stored events are redacted, the diagnostics screen and profile exports can still show current identifiers or user-selected values. Remove passwords, serial numbers, real SSIDs, exact locations, IP host portions, device UIDs, home paths, and unreviewed screenshots before asking for help.

Use [SUPPORT.md](../../SUPPORT.md) for public support and bug-report routes. For vulnerabilities, unsafe mutations, privacy leaks, exposed secrets, or rollback failures, follow the current [SECURITY.md](../../SECURITY.md) instructions. Its private-reporting prerequisite is not yet enabled, so request a private channel without disclosing details publicly.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| The app opened but no window appeared | Look for the menu-bar icon. The app is menu-bar-only by design. |
| The Wi-Fi name was not captured | Allow Location after the explanation, or explicitly use **Capture Without Wi-Fi**. After changing permission in System Settings, return and capture again. |
| A profile is Partial or Unavailable | Choose **Edit Profile**, inspect warning rows, reconnect the required device/service, or exclude an unavailable setting. Use **Review Available…** only when every omission is intentional. |
| Review shows no operation | The profile already matches the current readable state, or no included setting can be safely applied. Nothing needs to run. |
| Review refreshes instead of applying | The profile, capability, current value, or rollback evidence changed after the first review. This is a safety stop; inspect the new plan. |
| Profile storage shows an error | Use **Retry Loading** for a load failure or **Dismiss Error** after an ordinary failed operation. Do not edit managed files while the app is running. Restore through a reviewed export/import if needed. |
| A protected change is unusable | Choose **Revert Now** before the 15-second timer ends. Then confirm the original state in macOS System Settings and inspect the result. |
| The official DMG fails Gatekeeper | Stop; do not disable Gatekeeper or use **Open Anyway**. Confirm the release URL and checksum, then report the exact message without private data. |
| Launch at login was requested but is not enabled | Open **Settings → System**, compare the requested setting with **macOS registration**, approve it in macOS Login Items if prompted, then choose **Refresh Status** or **Retry Registration**. |

## Update

The app does not check the network for updates. After a public release exists, obtain updates manually from the canonical GitHub Releases page. Never replace an existing app with an ad-hoc CI artifact. Export saved profiles first when a release note calls out profile migration or recovery risk.

## Uninstall and delete local data

Removing the app does not automatically delete profiles or diagnostics.

1. If enabled, turn off **Settings → System → Launch Desk Setup Switcher at login** and confirm **macOS registration** is not enabled.
2. From the menu-bar app, choose **Quit Desk Setup Switcher**.
3. Move **Desk Setup Switcher.app** from **Applications** to the Trash.
4. To delete profiles, backup/quarantine files, and diagnostics, open Finder's **Go → Go to Folder…** and remove `~/Library/Application Support/Desk Setup Switcher/`. Export anything you want to keep first.
5. For a full preference reset, also remove `~/Library/Preferences/dev.ggulae.desk-setup-switcher.plist` while the app is not running.
6. If Location access was granted, optionally disable Desk Setup Switcher in **System Settings → Privacy & Security → Location Services**.

Profile JSON files exported to other locations are not tracked or removed by the app; delete those separately if wanted. Empty the Trash only after confirming no exported profile is needed. The current app does not ask for or store Wi-Fi passwords, so removing its files does not remove credentials managed by macOS.
