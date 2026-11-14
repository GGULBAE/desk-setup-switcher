# Keyboard repeat runtime application — 2026-11-14

## Problem and evidence

A user reported that Apply said key repeat succeeded but typing did not change. The installed 0.0.9 adapter wrote `KeyRepeat` / `InitialKeyRepeat` through CFPreferences and checked only those same saved preferences. It neither changed nor verified active HID repeat timing; planning could also skip a needed runtime update when the saved preference already matched the profile.

A narrowly scoped, read-only query on the development Mac confirmed that the saved preferences and public HID parameters disagreed. No device identifiers, profile contents, keystrokes, or complete diagnostics were collected. The screenshot's separate unverified input-volume result does not explain the keyboard success report and is outside this correction.

## Implementation

- `InputPreferencesAPI` separates saved preference access from active runtime nanoseconds. The concrete implementation uses public SDK declarations `IOHIDCopyCFTypeParameter` / `IOHIDSetCFTypeParameter`, public repeat keys, and a short-lived `IOHIDSystem` parameter connection. It releases service and connection handles on every path. There is no private API, event monitoring, injected keystroke, shell execution, or third-party configuration edit.
- Capture and post-Apply snapshots project active repeat timing. Global preference ticks map experimentally to 60 Hz units, rounded to integer nanoseconds. Native integral steps remove conversion roundoff on Capture; fractional imported values are not snapped to a slider step.
- Core owns `KeyboardPreferenceRollback`, optional session-only catalog evidence containing the prior saved numeric preference (or absent key) and exact original runtime nanoseconds. It is not part of schema-v1 profile settings. Older snapshot JSON still decodes, but absent paired evidence cannot authorize a write.
- Plan compares both saved and runtime layers. Apply writes and confirms both. Rollback independently attempts both original values even if either restore fails, then confirms both. The existing engine restores a partially failed operation before allowing another nonfatal operation to continue; failed recovery stops the transaction.
- Unreadable runtime access, invalid/Off timing, and unusable rollback values omit only the affected control. Native Off, brightness, mouse, scrolling, and function-key behavior remain outside the mutation path. Existing group/leaf inclusion policies remain unchanged.
- English and Korean failure/diagnostic messages explain saved/active disagreement without exposing raw device data. Runtime drift is reported with the stable `input.runtime-mismatch` diagnostic code.

## Public API references

The installed macOS SDK publicly declares the CF-type parameter functions in `IOKit/hidsystem/IOHIDLib.h`, repeat keys in `IOHIDParameter.h`, and the parameter connection type in `IOHIDShared.h`. Apple's [IOEventStatusAPI implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/main/hidsystem.subproj/IOEventStatusAPI.c) shows repeat parameters using nanoseconds. Apple's [keyboard filter](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDEventSystemPlugIns/IOHIDKeyboardFilter.mm) consumes repeat timing in nanoseconds and documents its 1/60-second minimum. Global preference keys and their tick mapping remain experimental, not a stable documented API guarantee.

## Verification

The final `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make verify` completed with exit code 0 on 2026-11-14. It passed 387 Swift Testing cases (including nine new keyboard regressions), the isolated native-popover XCTest, formatting/localization checks, all release-tooling mock suites, arm64/x86_64 Debug and Release builds, static analysis, DMG checksum/structure checks, and app metadata/resources verification. `git diff --check` also passed.

The separate opt-in `DESK_SETUP_LIVE_READ_TESTS=1` snapshot test passed against the corrected adapter. Independent public IOHID and AppKit read-only queries agreed on active repeat timing that differed from the saved preferences. This verifies the read path and defect diagnosis, not the corrected hardware write path.

Local development artifact: `artifacts/Desk-Setup-Switcher-0.0.9-unsigned.dmg` (arm64 and x86_64, minimum macOS 14.0). DMG SHA-256: `529c8f4e8d710ef78e284441004a70b3e01d9a83c8b1030c862c7375e06d21ee`. Packaged executable SHA-256: `62bd07483a4c1518fa5216b5d042cd78950e7b83a75cda6fa85e291e9412ee59`. This working-tree build is separate from the previously published v0.0.9 asset. It has not replaced the installed app or public release.

An initial bare `swift test` selected Command Line Tools and could not find XCTest. Setting `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the verification process selects the installed full Xcode without changing global developer settings.

No live keyboard mutation, perceived typing test, installation, app restart, publication, or push has been performed. A read-only discrepancy is evidence of the defect, not proof of the corrected live write path. Existing unrelated modifications and untracked files remain intact; completion items are not checked without committed evidence.

## Remaining hardware validation

Any live validation is a separate opt-in procedure: explicitly set `DESK_SETUP_LIVE_MUTATION_TESTS=1` for that procedure, capture both saved preferences (including absent keys) and exact active nanoseconds before changes, and have the user interactively review and confirm the app's keyboard-only Apply. The procedure must retain and exercise a restoration path for both original layers, independently verify restoration, and stop if that evidence cannot be retained. The flag documents test intent and does not itself trigger a mutation. Ordinary tests and CI never perform this procedure. Do not assume restoring a single captured profile restores a pre-existing saved/runtime mismatch.

Git paths: `Sources/DeskSetupCore/Engine/SystemSettingsAdapter.swift`, `Sources/DeskSetupSystem/Input/`, `Tests/DeskSetupSystemTests/InputPreferencesAdapterTests.swift`, `Tests/DeskSetupSystemTests/VisibleSettingEndToEndInvariantTests.swift`.
