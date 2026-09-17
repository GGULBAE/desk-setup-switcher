# Keyboard brightness retirement and unified editor reinstall — 2026-09-17

## Scope

The user authorized the Keyboard scope change, local reinstallation, commit, and push. Current source exposes exactly nine profile setting kinds: two Display values, five Sound values, and the two Keyboard repeat values. Keyboard brightness remains only as dormant schema-compatible data and is not captured, edited, planned, applied, verified, or rolled back. Display, Sound, and Keyboard now share one vertically scrolling editor without an internal rail or segmented selector.

This work did not authorize Capture, Apply, permission requests, login-item changes, or any live display, audio, network, mouse, or keyboard mutation. The only live actions were stopping the old app process, replacing its bundle, and launching the replacement.

## Exact-source verification

Implementation commit `ce58e61` was checked out in a detached clean worktree before final verification and bundle assembly.

- Strict Swift formatting, the generated Xcode-project check with 68 Swift files, English/Korean localization validation, and `git diff --check` passed.
- The deterministic SwiftPM run passed 373 Swift Testing cases across 41 suites with two explicit opt-in live-test skips. The isolated native-popover XCTest passed separately with one test and zero failures.
- SwiftPM Release built successfully with warnings treated as errors.
- Public asset verification and the full published, holding, private-preview, GitHub Pages, and local public-surface matrix passed. The clean site install reported zero dependency advisories.
- The canonical `make verify` entry point still stops before its Xcode stages with error 69 because the installed Xcode license has not been accepted. No process accepted that license on the user's behalf. The fallback used the checked-in source, Apple SDK/framework paths, deterministic mocks, and no live mutation flags.

## Installed bundle

The exact verified commit was built in Release configuration, assembled with the checked-in `Info.plist`, icon, English/Korean resources, and SwiftPM resource bundle, then ad-hoc signed and installed at `/Applications/Desk Setup Switcher.app`.

- Bundle identifier: `dev.ggulae.desk-setup-switcher`
- Version/build: `0.0.9` / `1`
- Executable architecture: `arm64`
- Installed executable SHA-256: `87f66cd1a81416a8899ea9e46b61ac81a56a4108dc43e0dbc078e7442444c701`
- Signature verification: strict/deep ad-hoc verification passed
- Startup: the running executable resolved to the exact `/Applications` path, and a read-only Core Graphics inventory reported zero visible layer-zero windows owned by the process

This is a local Apple Silicon development installation. It is not the canonical universal package, a notarized build, or a supported public release.

## Preservation and rollback

The previous installed app and mode-`0600` copies of both profile files were retained under the private mode-`0700` recovery directory `.build/reinstall-keyboard-retirement-20260917.qhh1my/`. The previous executable SHA-256 was `0798aac51fc001d52889aa1ddb4d552396b37dbaf1ec0ac7e89e48d19e163d65`.

Both profile files were byte-identical before replacement, immediately after replacement, and after startup. No profile file was rewritten by the reinstall. App-only rollback is recoverable by stopping the current process, moving the current bundle aside, and restoring `Desk Setup Switcher.installed-before.app` to `/Applications/Desk Setup Switcher.app`. The saved profile copies must not be restored merely to roll back the app, because that could discard later user edits.

## Evidence boundary

Installation and startup demonstrate only that the exact `ce58e61` Apple Silicon bundle is structurally valid, replaceable, launchable, and preserves profile storage. They do not prove installed-editor focus or scrolling, perceived repeat behavior, hardware Apply/read-back, or rollback. No app control was invoked after launch, and no system setting or TCC state changed. Keyboard brightness is intentionally outside the live product path and requires no hardware verification.
