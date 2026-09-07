# Profile editing and App Settings clarification

Date: 2026-09-07

## Behavior

- Profiles no longer render Last application history. Stored application summaries and the post-Apply result workflow remain intact.
- Display resolution/refresh/ColorSync and Sound output mute/input controls are directly visible within their owning step. The generic Advanced settings disclosure and its expansion state are removed.
- Network has one connection selector and one DHCP/manual IPv4 editor for the selected service. Browsing a connection changes only transient selection; inclusion switches still affect only the selected service. Unavailable included services retain their repair switches.
- Validation selects the owning step and, for service-specific IPv4 fields, the matching connection before requesting keyboard focus. Deterministic tests cover all IPv4 fields, indices 1 versus 10, unrelated fields, absent indices, and empty catalogs, alongside existing inclusion-preservation tests.
- App Settings replaces the System tab label and groups app behavior, Wi-Fi capture access, and on-demand diagnostics. Login registration details and refresh are available through Login item details; mismatches and retry remain visible. English and Korean copy, native keyboard controls, and non-color status cues are retained.

## Verification

Implementation commit: `3bf2324`.

The canonical non-live `make verify` gate passed: localization/lint, unit/mock tests, release-tooling tests, Debug/Release builds, universal Xcode builds, static analysis, and mounted unsigned-DMG/resource verification. The Swift Testing run passed 334 tests; the existing XCTest and isolated native-popover checks also completed successfully, with live opt-in checks remaining outside this evidence boundary.

The 18-fixture Settings offscreen matrix passed and every generated PNG was visually inspected. The fixtures cover English/Korean, light/dark, minimum windows, large/accessibility text, validation, unavailable audio, ColorSync, and DHCP/manual IPv4. Direct controls, warning/repair rows, fixed Save/Revert actions, and the App Settings sections retain their layout. Long forms continue to scroll; screenshots do not prove installed scrolling or keyboard behavior.

Reproduce the local render artifacts with the repository's full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 \
DESK_SETUP_REFINEMENT_EVIDENCE_DIR="$PWD/.build/profile-app-settings-2026-09-07" \
swift test --filter TrayOffscreenEvidenceTests.rendersSimplifiedProfileSections
```

Verification exercised the combined working tree, including pre-existing Apply Preview edits. Only this follow-up's profile/App Settings changes are committed here; the generated package is local working-tree evidence, not an exact-commit release candidate. The verified unsigned DMG SHA-256 is `af214010467f99f9e9f1a0f315d9e7208baec0ef6210315de9caa0d2de708570`. Final `git diff --check` and localization/lint passed after the documentation update.

These checks use synthetic/mock state. They do not establish installed keyboard/VoiceOver behavior, live TCC/login actions, or physical display/audio/network apply/rollback. The implementation verification above did not replace the installed app, push remotely, or publish. The subsequent user-authorized installation is recorded below.

## Authorized local installation — 2026-09-07

The user requested installation on the current Mac. The exact previously verified DMG (`af214010467f99f9e9f1a0f315d9e7208baec0ef6210315de9caa0d2de708570`) was mounted read-only; its ad-hoc-signed app was validated, staged, and moved to `/Applications/Desk Setup Switcher.app`. The old app was not running and was preserved in a build-local recovery directory with rollback instructions. The DMG was detached before launching the installed app.

The installed process runs from the expected `/Applications` executable path. The installed executable SHA-256 is `2969f417716fbd4021f84585f9926ac3557b6be52333f84c99905db104c9da89`; strict/deep signature verification and the `x86_64 arm64` architecture check passed. This packaged executable differs from the unsigned build output because packaging adds the ad-hoc integrity signature. The Korean App Settings resource is present, and profile primary/backup hashes are unchanged after launch.

This proves replacement, startup, and profile-file preservation only. No UI automation, profile Apply, permission prompt, login registration action, hardware mutation, or remote publication was performed.

## Next verification task

In an explicitly chosen installed build, manually inspect English/Korean tab navigation, scrolling, Save/Revert keyboard access, and service-specific validation focus. Keep Apply, permission changes, and login registration mutations out of that pass. Record observed limitations in README, the support matrix, and the completion ledger.
