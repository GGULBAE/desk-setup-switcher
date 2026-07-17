# Native UI structural reliability audit — 2026-07-17

## Scope and safety boundary

This follow-up was prompted by a user-provided installed-app screenshot in which the tray content remained visibly shifted toward one side. The report was persistent, not a one-time first-launch animation, so the review covered every app-layer SwiftUI/AppKit surface rather than only the empty tray: popover ownership and attachment, Settings/workflow window presentation, minimum-window layout, long Korean copy, simulated accessibility text, keyboard focus, and VoiceOver focus intent.

All implementation and automated verification used synthetic profiles, injected window state, and attached/offscreen AppKit hosts. No installed app was launched, no UI automation was used, and no display, ColorSync, audio, network, mouse, keyboard, TCC, Keychain, login-item, or third-party configuration was changed.

## Findings and corrections

| Area | Failure risk found | Correction |
| --- | --- | --- |
| Native popover safe area | The SwiftUI root and hosting wrapper both tried to ignore horizontal safe area after the hosting tree existed. A real `NSPopover` can publish asymmetric left/right exclusions, while dynamic `safeAreaRegions` or `additionalSafeAreaInsets` changes do not reliably invalidate SwiftUI's already-cached root proposal. Removing all safe areas also erased the native top/bottom chrome exclusion. | The popover now owns a public AppKit container view in front of the existing `NSHostingController`. The container reports `super.safeAreaInsets` with top/bottom preserved and left/right filtered to zero, so SwiftUI receives the selective safe area on its first attached proposal. The duplicate SwiftUI ignore modifiers and dynamic safe-area toggles are gone. |
| Persistent destination presentation | A visible window that never became key could leave a routing request waiting forever. Cancellation was producer-wide, so one cancelled duplicate caller could tear down another caller's presentation. Red-close could also leave a cancelled request attached long enough for a same-MainActor-turn reopen to join it. | One shared producer now has independently cancellable consumers, a bounded two-second liveness deadline, identity-guarded completion, and balanced activation accounting. Red-close detaches the current request before cancellation, so an immediate reopen owns a fresh request and stale completion cannot hide it. |
| Workflow minimum layout | Permission, dirty-draft, preview, safety, and result footers assumed a horizontal action row. Apply rows reserved fixed 70/80-point columns. Long Korean labels, long profile names, and accessibility text could compress, overlap, or move actions beyond the 520×360 minimum. | A custom adaptive action layout measures ideal button widths and stacks when required or whenever accessibility text is active. Preview/result headers and operation details switch between grids and vertical stacks. Visible destructive/apply button copy is short while full profile-specific meaning remains in the accessibility label. Scrollable bodies stay above fixed reachable actions. |
| Focus and accessibility transitions | New workflow states did not consistently choose a safe keyboard target, and some accessibility focus requests targeted children later combined into one accessibility element. | Permission, preview, dirty-draft, confirmation, result, and error states request their heading or combined status element for accessibility. The enabled safe Cancel/Revert/Close action receives keyboard focus; countdown output is exposed as one changing accessibility value. |
| Evidence quality | Earlier evidence did not combine the real minimum size, Korean, and simulated accessibility text for Settings and all workflow decision states. Transparent offscreen images could also be misread by image decoders. | New fixtures cover Settings at 680×480 and workflow at 520×360 in Korean with accessibility text. Workflow evidence is encoded as opaque high-quality JPEG and validates sampled bright/dark pixel ratios plus white background points. |

## Deterministic behavior proof

The selective popover boundary is tested with a native safe area of `top 3 / left 11 / bottom 5 / right 2`. The hosted SwiftUI view receives `top 3 / left 0 / bottom 5 / right 0`, and its padded probe occupies `x 16…352` and `y 21…297` in the 368×316 viewport. A three-way raster compares a zero-inset baseline, the filtered asymmetric boundary, and an intentionally unfiltered control: only the unfiltered control moves. This means removing the production filter causes the regression test to fail for behavior, not merely for an implementation accessor.

Window tests cover red-close before key, caller cancellation before and during presentation, two coalesced callers where only one cancels, visible non-key deadline completion, activation-policy balancing, ten reopen cycles, and a direct same-MainActor-turn red-close→reopen. Workflow policy tests cover measured horizontal/stacked frames, bounds and non-overlap, accessibility-size stacking, and safe initial keyboard focus.

The final focused run passed 52 tests across five safe-area, geometry, window-lifecycle, responsive-workflow, and attached-evidence suites; an independent reviewer also passed its 43-test structural subset. Integrated non-live `make verify` then passed 412 default cases (144 XCTest with five opt-in skips plus 268 Swift Testing cases across 35 suites with two default-disabled opt-in cases), Swift/Xcode Debug and Release, Analyze, and universal mounted-DMG verification. The package SHA-256 is `84bcdeac1f44de6381f93c8b9650132e26c4e9126c3d7137276db9c43274bb86`; no live flag was set, and the package was not installed or launched.

## Visual evidence

- [Settings, Korean minimum window with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/settings/16b-profile-ko-minimum-large-text.png)
- [Permission workflow, Korean 520×360 with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/workflow/26-permission-ko-minimum-large-text.jpg)
- [Dirty-Apply workflow, Korean 520×360 with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/workflow/27-dirty-apply-ko-minimum-large-text.jpg)

The Settings `TabView` offscreen host can capture an opaque black material strip at the top, and some AppKit-localized controls remain English under a forced test locale. Those are documented host limitations rather than installed rendering claims. The evidence is used for containment, hierarchy, action reachability, long-copy wrapping, and minimum-size review.

## Remaining native/manual boundary

Attached/offscreen AppKit proves the selective inset contract and contained SwiftUI layout, but it cannot prove the first frame of a real status-item `NSPopover`, its arrow/material/anchor, outside-click timing, real first-responder rings, or VoiceOver speech/rotor order. The next UI verification step is therefore a separately authorized installed-app smoke pass: inspect the first and repeated tray opens, red-close→reopen Settings/workflow behavior, keyboard-only traversal, and VoiceOver initial focus without confirming any hardware-setting mutation.
