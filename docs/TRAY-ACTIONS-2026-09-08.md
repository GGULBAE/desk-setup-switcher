# Compact tray profile actions — 2026-09-08

## Scope

- Replace each tray card's one-item More menu with a directly visible trash button. It enters the existing inline deletion confirmation, without a menu step. Cancel/Escape, unsaved-draft disclosure, busy locks, duplicate-delete protection, and persistence failure recovery are unchanged. No real profile is deleted during verification.
- Show **Apply / Edit / trash** on one horizontal action row. Korean labels are **적용하기 / 수정하기**. Both normal and available-items Apply still open the appropriate read-only preview; they never bypass review or invoke an adapter directly. Matched/unavailable profiles keep a disabled Apply button so card controls stay aligned. Button help retains the disabled reason or partial-plan meaning.
- Replace the passive matched/no-available-settings sentences with one blank caption line, including the same breathing room on ready/partial cards. Header status text and symbols remain; progress, safety confirmation, and other actionable disabled reasons remain visible.
- Preserve the six-setting profile scope, fitted/frozen tray sizing, current launch-at-login behavior, and the separate Settings sidebar menu. No `sfltool`, permission changes, hardware Apply, or additional profile settings are introduced.

## Verification

Focused tests cover localized labels, passive/active status policy, preview/confirmation routing, tray lifetime, and atomic deletion. Synthetic tray rendering covers English/Korean, light/dark, normal/enlarged text, deletion, transient states, and overflow. Short-name three-profile pixel assertions check a single aligned action row, a blank description line, and the bounded closing inset.

- Focused policy/routing/deletion/render run: 23 tests in four suites passed with warnings treated as errors.
- Final synthetic tray matrix: all 21 fixtures passed, including the additional image assertions for aligned Apply/Edit/trash centers and empty caption space. Korean/English short-name fixtures both fit at 368 × 408 points with a bounded bottom inset. Light/dark, long-name, enlarged-text, overflow, and deletion-confirmation samples were visually inspected.
- Primary `make verify`: passed localization/lint, the parallel XCTest run and 350 Swift Testing tests, the isolated native popover regression, release-tooling mocks, Debug/Release builds, static analysis, universal packaging, mounted-DMG verification, and release metadata/resource checks. Opt-in live tests remained disabled. No live profile deletion, settings Apply, or permission request is part of this verification.

Verification uses the current working tree. Existing Apply Preview and installation-document edits are preserved outside this milestone's commit.

## Local replacement

The verified local 0.0.9/build-1 app replaced `/Applications/Desk Setup Switcher.app` after a normal quit. The installed executable passed strict code-signature verification, matched the mounted package digest, and launched from that exact installed path. Both profile files remained byte-identical after startup. The consented launch-at-login ON preference was retained; no registration or Keychain action, `sfltool`, live Apply, or real profile deletion was performed.

- DMG SHA-256: `bf81123565dec08cba928af52617c499f87e1d78497012e25fd73e5126aeb0dc`.
- Packaged/installed executable SHA-256: `ad6c54b81784d0ad4ee44de19fbf3e5e4be0bb64d2adaa62a21bbce3235235e0`.
- Private recovery: `.build/installed-app-audio-tray-actions-20260908.BIpMLS/` contains `Previous.app`, both profile backups, and `RESTORE.md`. These local backup contents are not committed.

## Next bounded check

Review the updated installed tray at the user's usual window/text size: confirm direct trash visibility, aligned Apply/Edit controls, and the reserved blank line. This check does not delete profiles, execute Apply, change permissions, or change the current feature scope. Record any discrepancy and keep README status current.
