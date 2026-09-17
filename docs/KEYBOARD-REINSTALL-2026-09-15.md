# Keyboard settings local reinstall — 2026-09-15 / blank-window follow-up — 2026-09-17

> Historical evidence: this record describes the superseded three-control Keyboard build. Current source preserves keyboard brightness only as dormant legacy profile data and does not capture, edit, or apply it; Display, Sound, and the two repeat controls now share one vertically scrolling editor.

## Scope

The user authorized replacing the local app with the current Keyboard-settings source and launching it. On 2026-09-17 they also reported a recurring empty system-owned Settings window and asked to continue. The follow-up removes the empty SwiftUI `Settings` scene while preserving the app-owned AppKit Settings window and `⌘,` command route. This operation did not authorize Capture, Apply, an Input Monitoring request, login-item changes, UI automation, or any display, audio, network, mouse, or keyboard mutation.

Full Xcode 27.0 is installed, but its license has not been accepted on this Mac. The canonical `make verify` and Xcode universal-package path therefore stop before building. No process accepted the license on the user's behalf. The existing DMG was older than the current source and was not reused.

## Installed bundle

The exact staged source was built with SwiftPM in Release configuration with warnings treated as errors, then assembled as a local app bundle with its checked-in `Info.plist`, icon, English/Korean resources, and SwiftPM resource bundle. The latest reinstall includes the semantic Keyboard editor: native-style discrete slow-to-fast and long-to-short repeat scales, a continuous dim-to-bright backlight scale, no duplicate slider labels, and no raw numeric fields. It also replaces the empty system Settings scene with a noninserted lifecycle scene, so only the existing app-owned Settings presenter can create a visible settings window. The app was ad-hoc signed and installed at `/Applications/Desk Setup Switcher.app`.

- Bundle identifier: `dev.ggulae.desk-setup-switcher`
- Version/build: `0.0.9` / `1`
- Executable architecture: `arm64`
- Installed executable SHA-256: `0798aac51fc001d52889aa1ddb4d552396b37dbaf1ec0ac7e89e48d19e163d65`
- Signature verification: strict/deep ad-hoc verification passed
- Runtime linkage: public CoreHID remains weak-linked
- Startup: the executable running after launch resolved to the exact `/Applications/Desk Setup Switcher.app` path; a read-only Core Graphics window inventory reported zero visible windows owned by the process after startup

This is a current-source, local Apple Silicon development installation. It is not a universal `arm64+x86_64` package, a verified DMG, a clean committed build, or a supported public release.

## Preservation and rollback

Immediately before the latest replacement, the installed app and the primary profile, backup profile, and app-preference files were copied into the private mode-`0700` recovery directory `.build/reinstall-keyboard-blank-settings-20260917.C4vOra/`. `RESTORE.md` in that directory describes app-only rollback. Profile or preference snapshots must not be restored merely to roll back the app, because doing so could discard later user changes.

The primary and backup profile files remained byte-identical after installation and launch:

- Primary profile SHA-256: `241036a86b9534938a1bf263ca3b6dbb713940bff430f391774dc3c968d6a402`
- Backup profile SHA-256: `888fe4880b473684a237e0eb9631efecc5eaecca4d43d2e4e54bdfe66e3834bb`

The saved login consent/request state and prior SwiftUI Settings-window frame entry were semantically unchanged. SwiftUI recorded only the disabled lifecycle `MenuBarExtra` insertion flag as `false`; it did not add a visible status item or window. No LaunchAgent was created and no startup registration was changed.

## Evidence boundary

Installation and startup demonstrate only that this Apple Silicon local bundle is structurally valid, replaceable, and launchable while preserving profile data. The zero-window startup observation and deterministic lifecycle-scene regression prove that the removed empty SwiftUI Settings scene cannot be restored at launch; no UI automation or installed Settings interaction was used, so this is not a complete manual routing/focus check. No app control was invoked after launch. Keyboard Capture, repeat settings, Input Monitoring, brightness discovery, Apply/read-back, and rollback were not exercised on hardware, so the current Keyboard milestone remains deterministic unit/mock evidence only. The slowest enabled repeat step is not mislabeled as Off; true repeat-disable capture/apply/rollback remains unsupported until it has a separate typed runtime state. The canonical full non-live gate remains blocked until the user reviews and accepts the installed Xcode license.
