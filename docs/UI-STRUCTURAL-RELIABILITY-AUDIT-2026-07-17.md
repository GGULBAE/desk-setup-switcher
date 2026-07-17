# Native UI structural reliability audit — 2026-07-17

> **Evidence status:** This is the preceding selective-safe-area, window-liveness, responsive-layout, and synthetic-evidence audit. The final persistent-shift root cause, attached-native regression, installed package results, and current safety record are authoritative in the [UI/UX simplification and installed-app audit](UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md) and its [evidence index](evidence/ui-ux-installed-2026-07-17/README.md).

## Scope and safety boundary

This preceding follow-up was prompted by a user-provided installed-app screenshot in which the tray content remained visibly shifted toward one side. The report was persistent, not a one-time first-launch animation, so the review covered popover safe-area boundaries, Settings/workflow window presentation, minimum-window layout, long Korean copy, simulated accessibility text, keyboard focus, and VoiceOver focus intent. A later genuine attached-`NSPopover` test isolated the final remaining shift to application code resetting AppKit's wrapper origin; that correction belongs to the current audit linked above.

Implementation and automated verification used synthetic profiles, injected window state, and attached/offscreen AppKit hosts. A subsequent separately authorized follow-up reinstalled the verified package to `/Applications` and inspected only bounded tray/window geometry. Neither phase invoked Apply, Capture, TCC, login-item, display, ColorSync, audio, network, mouse, keyboard, Keychain, or third-party configuration mutation.

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

The focused structural run passed 52 tests across five safe-area, geometry, window-lifecycle, responsive-workflow, and attached-evidence suites; an independent reviewer also passed its 43-test structural subset. The final integrated gate then passed 446 checks: 144 XCTest cases, 301 Swift Testing cases across 38 suites, and one separately executed native `NSPopover` regression. Swift/Xcode Debug and Release, Analyze, checksum, mounted metadata/resources/`x86_64 arm64`, and ad-hoc/no-Developer-ID verification all passed. The final DMG SHA-256 is `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`.

## Visual evidence

- [Settings, Korean minimum window with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/settings/16b-profile-ko-minimum-large-text.png)
- [Permission workflow, Korean 520×360 with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/workflow/26-permission-ko-minimum-large-text.jpg)
- [Dirty-Apply workflow, Korean 520×360 with simulated accessibility text](evidence/ui-structural-fix-2026-07-17/workflow/27-dirty-apply-ko-minimum-large-text.jpg)

The Settings `TabView` offscreen host can capture an opaque black material strip at the top, and some AppKit-localized controls remain English under a forced test locale. Those remain documented host limitations rather than installed rendering claims. The evidence is used for containment, hierarchy, action reachability, long-copy wrapping, and minimum-size review; installed geometry is recorded separately below.

## Installed geometry follow-up summary

The current [installed audit](UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md) supersedes this document for final root cause and installed evidence. In summary, the DMG was reinstalled to `/Applications`; the installed executable SHA-256 is `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305`. Package and installed-build checks verified metadata, resources, ad-hoc/no-Developer-ID signature status, and both `x86_64` and `arm64` slices.

- Twenty measured popover opens reported exact center delta `0`.
- Requesting a `500×300` Settings window clamped it to `680×480`; the normal `900×568` frame was retained across ten opens.
- Requesting a `500×300` workflow window clamped it to `520×392`. Its initial frame was `620×532`, its content was `620×500`, and Escape closed it.
- Apply, Capture, TCC, login, and system-setting mutations were not invoked.

This supersedes the audit's earlier “not installed” limitation for the measured geometry above only. It does not turn offscreen focus intent into a VoiceOver result and does not establish focused-control accessibility state.

## Remaining native/manual boundary

The installed follow-up closes the measured centering and minimum-window geometry questions, but it does not complete full keyboard traversal, native bilingual interaction, real first-responder-ring review, VoiceOver speech/rotor order, or focused-control AX observation.

The bounded P2 follow-up is limited to empty-tray Capture prominence; Duplicate/Reorder/Import/Export hierarchy; dirty-draft Export semantics; Included-toggle ambiguity; VoiceOver behavior for `DisclosureGroup`; Advanced Diagnostics' 700-point minimum versus Settings' 680-point minimum; minimum-size and AX fixtures for About, protected-change safety, and results; `⌘,` tab forcing; and generic storage-error prominence. It must not expand into Apply or Capture execution, TCC/login changes, system-setting mutation, or unrelated storage/release work.
