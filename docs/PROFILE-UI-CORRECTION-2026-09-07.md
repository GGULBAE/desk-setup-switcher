# Profile navigation and Advanced settings correction

Date: 2026-09-07

## Scope

The prior `3bf2324` change flattened Display/Sound controls beyond the requested Advanced-settings scope. `ViewThatFits` also chose navigation using the selected detail content's intrinsic width, so the same window could show a rail for Network and a segmented selector for Display/Sound.

- Restore the compact Display arrangement and Sound output/volume cards, with resolution/refresh and input/mute inside Advanced settings. Keep Network's connection/IPv4 cards, the saved-profile sidebar, App Settings, and Last application removal.
- Choose the rail using only the editor viewport and accessibility text. Switching sections or expanding details cannot change navigation. Narrow/accessibility layouts retain the segmented selector.
- Remove ColorSync from the visible registry (nine kinds), new display captures, capture summaries, and editor controls. Normalize old color leaves to excluded at load/import and Apply preparation, preserving values for schema compatibility. Internal low-level ColorSync primitives retain mock rollback tests but are not exposed by the profile workflow.
- Retain native disclosure keyboard/AX semantics and non-color inclusion cues. Validation opens the owning disclosure or Network connection before focus transfer.

## Verification

Implementation commit: `cde1903`.

The 337-test Swift Testing suite and the isolated native-popover regression passed. The Settings test covers 19 English/Korean, light/dark, minimum/accessibility, validation, unavailable-audio, Network, and expanded-detail fixtures. Standard-width cases assert actual numbered-rail accent pixels rather than recalculating a declared layout policy. The changed Display/Sound basic and expanded screens, compact/large-text layouts, and validation view were visually inspected. The canonical `make verify` gate passed: localization/lint, XCTest and Swift Testing, isolated native popover, release-tooling regression guards, Swift and universal Xcode Debug/Release builds, Analyze, DMG checksum/mounted resources, and app-bundle compatibility checks. The initial run exposed a timestamp-sensitive new test; a fixed synthetic timestamp resolved it, and the complete gate was rerun successfully. No hardware setting Apply, UI automation, explicit permission/login action, remote push, or publication was performed. The user's unrelated Apply Preview edits are preserved; combined-working-tree test/package evidence is not an exact-commit release artifact.

## Authorized corrected-build installation

The verified development DMG SHA-256 is `a89b99b0109328902eb4727d10dfbc32c8c2b25879cbfdec951eaefdfca72e3e`. It was mounted read-only and its app was staged and verified before replacement. The running app accepted a normal AppKit termination request and exited; no force quit or automated save/discard choice was used.

The old app and both profile files were preserved in the private build-local recovery directory `.build/installed-app-correction-20260907.c4GyJf/`, with rollback instructions. The corrected app was installed at `/Applications/Desk Setup Switcher.app`, strict/deep signature verification passed, the image was detached, and the installed executable was launched.

Installed/package executable SHA-256 is `583cde7777786b15271e18e3aae1da658db7039d51358f8ff99f39de11813759`, with `x86_64 arm64` slices and valid Korean resources. The unsigned build executable differs because packaging applies an ad-hoc integrity signature.

A temporary value-free audit used the current `ProfileJSONCodec` to compare the normalized pre-install document with the persisted post-launch document. Profile IDs, ordering, values, applicability, and metadata matched (allowing only sub-microsecond ISO-8601 date rounding); the post-launch file required no further normalization. No profile content or device identifier was printed. This proves profile preservation after the intended applicability normalization, not byte-for-byte unchanged files.

This installation establishes replacement, startup, and data preservation only. Installed control interaction, keyboard/VoiceOver behavior, and hardware apply/rollback remain unverified.

## Next verification task

On the corrected installed build, manually check Display → Sound → Network and expand/collapse Advanced settings at one unchanged window size, then at minimum width. Confirm Save/Revert and invalid-field keyboard focus, without Apply, permission, or login-item changes. Record any observations in README and the support/completion records; do not claim hardware or full VoiceOver verification.
