# Grouped Sound sections — 2026-09-07

## Presentation contract

Sound has two native section cards, **Output** and **Input**. Each contains its own device picker and volume control, labelled **Device** and **Volume** inside the card. Device and volume retain separate inclusion switches, target-device capability resolution, validation focus, and unavailable-volume repair controls. Accessibility labels keep the full input/output context; section headings, text/symbol inclusion cues, and native keyboard controls remain present. Existing English/Korean labels are reused.

This is a UI-only follow-up to the [minimal profile scope](MINIMAL-PROFILE-SCOPE-2026-09-07.md). Display/Sound navigation, the six captured/applied setting kinds, persistence, legacy exclusions, and transaction behavior are unchanged. No adapter or core logic is modified.

## Verification status

Implementation commit: `b6a8723` (local only; no push or new CI run).

The 19-fixture offscreen matrix passed in 105 seconds and exported 19 PNGs plus metadata to `.build/audio-grouping-ui-2026-09-07/` (log: `.build/audio-grouping-ui.log`). Seven Sound renders were visually inspected: Korean normal/full-height/minimum/accessibility text, English dark/large text, and unavailable-volume repair. The regression fixture checks two continuous section surfaces in the actual full-height Korean Sound render, rather than four independent option cards. English/Korean, dark, minimum-window, large-text, unavailable-volume, validation, and stable-navigation fixtures remain covered. The full canonical `make verify` retry passed (`.build/audio-grouping-verify-retry.log`): lint/localization, 195 XCTest cases (five opt-in skips), 341 Swift Testing cases in 39 suites (two opt-in skips), the isolated native popover regression, release-tooling safety mocks, Swift/Xcode Debug and Release, Analyze, packaging, and mounted metadata/resources/architectures/signature checks. `git diff --check` passed.

No live hardware setting, permission, login-item, or third-party configuration mutation is performed. Synthetic rendering does not prove installed keyboard/VoiceOver behavior or hardware Apply/rollback. Existing unrelated Apply Preview work is preserved and excluded from this milestone's commit.

The first canonical attempt stopped in the release collector harness after its watchdog timed out and process-group cleanup returned `EPERM` (`.build/audio-grouping-verify.log`). An unchanged standalone rerun passed all 132 collector assertions (`.build/audio-grouping-collector-retry.log`). No timeout, permission check, or safety guard was weakened. The complete canonical retry is recorded separately.

## Authorized local installation

- Installed and launched `/Applications/Desk Setup Switcher.app`, version `0.0.9` / build `1`, after a normal quit. No force quit or draft discard was used.
- DMG SHA-256: `f9160dc54d1c276f90ff3ac565cadc0e309b641f7a7d3ae2b3fe6e4846932692`.
- Mounted/installed ad-hoc-signed executable SHA-256: `8f19f3a778f89b1058e340f0e3142afa8077ad48b6bc868a84d567a73260adb9`.
- Unsigned build executable SHA-256: `d14b1066e8b681caa91bb6794c2638146a319816f9092284508edc6719a9cfb3`; the package copy has a different digest because of its ad-hoc signature.
- Exact `arm64+x86_64`, strict signature verification, the running installed path, and both profile files' byte-for-byte equality after startup were checked. The DMG was detached.
- Private recovery directory: `.build/installed-app-audio-20260907.pNHfAA/` (0700), with `Previous.app`, both profile backups (0600), and `RESTORE.md`. No user data was removed.
- The package includes the pre-existing local Apply Preview edits; those changes remain outside this milestone's commit. Nothing was pushed, uploaded, or published. Installed keyboard/VoiceOver and physical Apply/rollback remain unverified.

## Installed interaction follow-up

The user requested a standard/minimum-window keyboard and scrolling check and a push. The installed process was running and its executable still matched the mounted/installed digest above. Two attempts to connect to `/Applications/Desk Setup Switcher.app` through native Computer Use timed out before returning a usable accessibility tree or screenshot. A bundle-ID lookup was ambiguous because build copies share the identifier; the exact installed path was retained. No keyboard, scroll, Save, Apply, or permission action was performed. This is a blocked capture attempt, not completed interactive or visual-audit evidence. The next bounded check is to retry after the user opens Profiles → Sound; a usable screen connection is still required. Native interaction and VoiceOver remain unverified.

This follow-up changes documentation only. The preceding complete `make verify` result covers the unchanged app and tests; documentation lint and diff checks are rerun before its commit. Push and CI outcomes are reported separately and do not turn the blocked interaction check into a pass.

## Next verification

Review the installed Sound sections using normal user keyboard and scrolling at standard and minimum window sizes, without Apply or permission changes. Record any issue and update README/support status. Hardware mutation requires a separate opt-in with preflight and rollback.
