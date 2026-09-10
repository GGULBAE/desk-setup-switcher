# Tray current-profile clarity and App Settings cleanup — 2026-09-10

## Scope

- The tray no longer renders a separate recent Apply result card below the profile list. Apply result state remains available to the protected workflow and diagnostics; removing the tray card does not change planning, execution, persistence, verification, or rollback.
- A profile whose fresh normal plan has no remaining operation is presented as the current setup. Its card uses an accent-tinted background, a visible accent border, and a filled checkmark badge with **Current setup / 현재 설정**, so the state does not rely on color alone.
- The tray Apply button uses the `play.fill` symbol beside its localized label. Edit retains its pencil symbol, and both continue to expose profile-specific accessibility labels.
- App Settings no longer shows the always-present **Login item details** disclosure. Opening App Settings performs a read-only status refresh. A requested/effective mismatch still shows the macOS status and **Refresh Status**; failed registration still adds **Retry Registration**. The launch toggle remains the only control that changes the requested state.

## Verification boundary

- `swift build` passed.
- Focused tray policy, geometry, and popover tests passed: 32 tests across three suites.
- The Korean compact three-profile offscreen fixture passed and was visually inspected. It contains one accent-emphasized current card, visible text/symbol state, Apply/Edit icons, and no bottom Apply result card.
- The Korean minimum-size accessibility-text App Settings fixture passed and was visually inspected. It omits the technical disclosure while retaining mismatch text and the refresh action.
- Full repository `make verify` passed, including lint/localization checks, 359 Swift Testing tests, the native popover XCTest, release-policy checks, Debug/Release builds, static analysis, and universal `arm64`/`x86_64` unsigned DMG packaging verification.
- Final `git diff --check` passed after this evidence record was updated.

## Authorized local reinstall

- Behavior commit `f1af22a` was pushed to `origin/master`. A fresh package was built from that exact commit rather than from the remaining unrelated working-tree changes.
- The verified unsigned development DMG SHA-256 is `21d7f15cd95c1e06accf84e4c554f392995ab22c9faf69fa16b73c64cca828b0`. Its mounted app passed strict/deep ad-hoc signature verification, reports version `0.0.9` / build `1`, and contains `arm64` and `x86_64` slices.
- The mounted and installed executable SHA-256 is `a5988a1f4e41da44a6d7189e020acd593682fa3ed91ed4643c25420fd6e1168a`. The previous app was normally quit and moved out of `/Applications` into private recovery directory `.build/reinstall-current-profile.WXh000/`, mode `0700`, before the verified candidate replaced it.
- `profiles.json` and `profiles.backup.json` remained byte-identical before replacement and after startup. Their contents and device identities are not recorded here. The existing consented launch-at-login preference and consent version remained `1`; no preference or registration change was requested.
- The DMG was detached before launching the installed path. `/Applications/Desk Setup Switcher.app/Contents/MacOS/DeskSetupSwitcher` was then observed running with the installed executable hash above.

No Capture, Apply, login-item registration, permission, Keychain, display, audio, network, mouse, or keyboard mutation was run. The screenshots are deterministic synthetic/offscreen evidence, and the local reinstall proves package replacement/startup only—not installed UI interaction, login-after-reboot, or hardware behavior.
