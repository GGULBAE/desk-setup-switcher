# Profile spacing, fitted tray, and explicit login requests — 2026-09-08

## Requested changes

- Remove the redundant Display/Sound detail title, explanation, and divider. Keep the existing numbered rail / compact segmented navigation and the Output/Input sections. The content container retains a localized section name, validation identifier, and group focus target.
- Add 12-point insets around sidebar management actions, including the trailing edge by the divider. Keep the fixed Save/Revert action bar. Increase the form's closing inset to 24 points.
- Replace the one-to-three-profile fixed-height assumption with a one-shot pre-open measurement of the same localized SwiftUI content at 368 points. Measurement omits the ScrollView and its scroll/focus tasks and does not attach a visible window. The viewport rounds up, clamps to the screen/560-point maximum, and stays frozen for that open generation. Empty and overflow states retain their existing policies; invalid measurements use deterministic fallbacks.
- Stop automatically registering a saved ON login preference when the app starts. Startup/status refresh can observe registered, missing, unavailable, and approval-required states without calling register. Explicit ON/Retry remains the registration path; explicit OFF and existing stale/legacy opt-out cleanup remain intact.

The previously reported `sfltool` prompt came from a separate installation diagnostic command, not an app feature. No invocation is added or run for this task. No Keychain, login-registration, or other permission changes are part of automated verification.

## Verification

Focused mock tests cover startup/status observation, explicit retry, duplicate ON, OFF, registration failure, per-open fit/freeze/reopen, invalid-fit fallback, screen clamping, and spacing policy. Synthetic English/Korean short-tray fixtures mirror the reported matched/partial/unavailable card combination and check the actual closing inset from rendered pixels. The existing settings matrix checks heading removal and retained two-card Sound grouping.

- Focused login, geometry, popover, and profile tests: 38 tests passed with warnings treated as errors.
- Synthetic rendering: all 21 tray fixtures and 19 profile/App Settings fixtures passed. The short-name, three-profile fixture fits at 368 × 419 points in Korean and 368 × 451 points in English; pixel assertions keep the closing inset between 12 and 28 points. Light/dark, narrow/large-text, validation, and overflow samples were visually inspected. The detail titles are absent, navigation and Output/Input grouping remain, and the fixed save bar stays separate from scrolling content.
- Primary `make verify`: passed, including localization/lint, the parallel test suite (347 Swift Testing tests plus the XCTest run), the isolated native popover test, release-tooling mock tests, Debug/Release builds, static analysis, universal packaging, mounted-DMG verification, and release app metadata/resource checks. Opt-in live tests remained disabled. `git diff --check` also passed.

Verification uses the current working tree, including the pre-existing Apply Preview changes. Those changes and earlier installation documentation remain preserved and excluded from this milestone's staged diff. No live profile Apply, display/audio/network mutation, authorization prompt, reboot, or installed keyboard/VoiceOver result is claimed by synthetic/mock verification.

## Local replacement and startup

The verified local 0.0.9/build-1 package replaced the installed app at `/Applications/Desk Setup Switcher.app` after a normal quit. The replacement passed strict code-signature verification, launched from that exact path, and matched the mounted package's executable digest. Both `profiles.json` and `profiles.backup.json` remained byte-identical after startup. The consented launch-at-login preference stayed ON; no new registration, preference write, `sfltool`, Keychain inspection, or authorization action was performed during installation verification. Effective macOS login registration and behavior after reboot were not re-tested.

- DMG SHA-256: `bb8065865b779f4ce0233b84c8df64eb4d34a66159fbad015ca6c3fe117272de`.
- Packaged/installed executable SHA-256: `e3b695452ec579c5a82d8a3a05ce910654a7c85a0cab2085d676025bbebe41c1`.
- Private local recovery: `.build/installed-app-audio-spacing-20260908.Ukl31b/` contains `Previous.app`, the two profile copies, and `RESTORE.md`. This is recoverable replacement, not profile deletion. No backup contents are committed.

## Next verification boundary

Check the installed profile sidebar/menu spacing, tray close/reopen and scroll behavior, and keyboard/VoiceOver section navigation at normal and enlarged text sizes. Do not apply a profile or change login preferences during that UI check. Record exact results and remaining limitations here and keep README verification status current.
