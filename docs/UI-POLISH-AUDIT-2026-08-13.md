# UI polish audit — 2026-08-13

## Scope and current result

This follow-up tightens the fixed-width tray, profile editor, workflow spacing,
and localization coverage without changing Capture, preview, Apply, rollback,
adapter, profile-schema, or window-lifecycle semantics. The implementation and
focused deterministic/offscreen checks pass. The final integrated non-live
`make verify` also passes on the current implementation: 194 XCTest cases, 331
Swift Testing cases across 39 suites, the separately isolated native popover
regression, release tooling, Swift/Xcode Debug and Release builds, Analyze, and
mounted universal-DMG verification all completed successfully. The generated
unsigned development DMG has SHA-256
`1b1b2d5c0bf0b3dcfe7155ecae94648ffde693f8fffa7c1f427cd2e83b02f96e`.
The current `git diff --check` passes. Behavior-focused commit `015e6bb`
records the implementation, tests, and this audit together. This record does
not claim an install, CI run, upload, tag, or publication.

The historical M4.8 and M4.11 records remain unchanged. This document is the
separate M4.12 working-tree evidence boundary.

## Implemented UI decisions

| Surface | M4.12 decision | Deterministic boundary |
| --- | --- | --- |
| 368-point tray | At every accessibility Dynamic Type size, the fixed-width tray moves Capture, Settings, and Quit into a dedicated row below the title and stacks the profile-card primary action above Edit/Delete. | Policy tests cover standard, `accessibility1`, `accessibility3`, `accessibility4`, and `accessibility5`. The tray width and existing action/disposition semantics are unchanged. |
| Recoverable tray error | A destination, profile-deletion, or other operation error is the first card in the tray scroll, with a context-correct heading. One top scroll/focus path keeps Dismiss visible; after a deletion error is dismissed, focus returns to the pending confirmation's safe Cancel action. | Source policy and the Korean handoff fixture assert the top anchor and Dismiss focus target; model regressions cover same-target re-emission, error-first reopen behavior, stale-focus cleanup, and deletion Cancel restoration. A raster bounds the error card inside the fixed tray viewport. This does not claim installed keyboard or focused-control AX behavior. |
| Profile editor | Option rows use a flatter eight-point leading inset, eight-point corner radius, quieter normal background/border, and stronger background, border, and warning boundary when Increase Contrast is active. Inclusion is one non-color label—**When applying · Included** or **When applying · Not included**—paired with its symbol and switch. At accessibility sizes, its visible summary has no line limit or fixed minimum/maximum width. Profile, name, icon, imported-symbol, Revert, and Save labels now use the explicit app localization boundary. | Presentation/style policy tests cover both inclusion states, symbol/value/help semantics, inline/stacked width policy, unrestricted accessibility summary sizing, flatter row metrics, and stronger Increase Contrast values. This is source/deterministic evidence, not a claim about every installed display appearance. |
| Workflow roots | Apply Preview, result details, protected-change safety, workflow errors, permission flows, and dirty-draft decisions share one 20-point content-inset token. | A source-contract test binds all six app-owned roots to the shared token and rejects the former 24-point padding. Apply Preview retains its existing single review-to-decision scroll sequence, top-reset behavior, footer/action reachability, Escape cancellation, and no default Return shortcut for Apply. |
| Localization | Static-key validation now scans Swift files recursively under the app target while excluding only the generated resource accessor. The five previously uncovered nested-surface keys—Dismiss, Settings unavailable, destination unavailable, destination could not be shown, and the no-confirmed-profile-match tooltip—have exact English and Korean values. Profile-deletion and generic-operation error headings are also exact in both languages. | English/Korean key parity, duplicate, placeholder, recursive static-key, and exact runtime-translation contracts cover the nested Settings, Tray, and Workflow source paths. |

## Focused verification

These are results from separate focused selections and must not be added
together as a new integrated-suite total.

| Selection | Result |
| --- | --- |
| Tray and profile policy tests | 19 passed |
| Runtime localization tests | 9 passed |
| Workflow state/action tests | 19 passed |
| Responsive workflow layout tests | 5 passed |
| Current attached/offscreen matrix tests | 4 passed across the expanded current matrix, followed by selected focused captures |
| Final integrated `make verify` | Passed: 194 XCTest + 331 Swift Testing cases across 39 suites + one isolated native popover regression; release tooling, builds, Analyze, package, and mounted universal-DMG verification also passed |
| Current working-tree `git diff --check` | Passed after the final documentation follow-up; repeat before commit if the tree changes |

The expanded matrix includes the Korean accessibility fixtures
`12c-partial-ko-accessibility3` for a partial tray profile and
`25-audio-ko-accessibility5` for the Settings audio editor. It also checks the
handoff error card's viewport bounds and requires tray and Apply Preview PNG
output to be opaque. These captures remain synthetic, non-mutating review
material. This documentation pass does not add or replace tracked images,
public screenshots, demo media, checksum manifests, or release-asset
provenance.

## Safety and evidence boundary

All focused checks use source policy, deterministic models, synthetic profiles,
isolated stores, and attached/offscreen app-owned surfaces. They do not invoke
Capture, Apply Profile, TCC changes, login-item changes, diagnostics clearing,
Keychain writes, or display, ColorSync, audio, network, mouse, or keyboard
mutation. No installed-window, real macOS Increase Contrast/text-size,
complete keyboard-order, focused-control AX, VoiceOver, or hardware rollback
claim is added.

The existing safety and support boundaries in
[SUPPORT-MATRIX.md](SUPPORT-MATRIX.md) remain authoritative. Full VoiceOver
certification remains excluded and unclaimed; keyboard behavior, accessible
names/values/help, localized English/Korean copy, and non-color state cues remain
required.

## Unclaimed follow-up evidence

Installed native accessibility settings, full keyboard/focused-control AX,
VoiceOver, CI, and hardware mutation/rollback remain separate evidence and are
not implied by the completed local package gate.
