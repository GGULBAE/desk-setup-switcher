# UI/UX simplification and installed-app audit — 2026-07-17

## Outcome

The persistent left-shifted tray UI was caused by an ownership violation between AppKit and SwiftUI: after `NSPopover` attached and positioned its content wrapper inside the asymmetric arrow/chrome shell, application code reset that native wrapper's frame origin to zero. The entire SwiftUI tree therefore moved relative to the popover shell. The fix leaves the attached wrapper geometry to AppKit and synchronizes only the hosted SwiftUI child to the wrapper's local bounds.

The audit also removed two related classes of UI instability before they could surface in normal use:

- Persistent Settings and workflow windows now own their native frame. SwiftUI root or tab changes cannot resize them through `NSHostingController` intrinsic sizing.
- Minimum sizes are enforced both when a window is presented and while AppKit processes a resize. This protects against legacy undersized frames and runtime weakening of `contentMinSize`.
- Async preparation, permission, capture, and save paths use request UUID or generation ownership. Deletion instead uses an in-flight profile-ID gate and commits presentation state only after persistence succeeds.
- Permission, capture, apply, and error states expose one clear decision set. Labels describe the real action, terminal states close predictably, and retry is shown only when the action actually retries.

The final package was rebuilt, installed at `/Applications/Desk Setup Switcher.app`, and exercised directly. Every sample from the first through the 20th tray open was centered; Settings and workflow minimum-size clamps held in the installed process. No profile Apply, Capture, TCC change, login-item change, or display/audio/network/input mutation was performed.

## Product goal and simple-flow contract

The goal of this pass was not to add features. It was to make the existing app behave as a small, predictable menu-bar utility:

1. Open the tray and see profiles or one honest empty state.
2. Choose Capture, Review/Apply, or Settings.
3. If a decision is required, show one compact window with a safe secondary action and only the choices that can really run.
4. Show the result, then close without leaving stale progress, duplicated errors, or hidden work behind.

The implementation follows these UI rules:

- Native containers own native geometry; SwiftUI owns layout inside the proposed bounds.
- One state has one authoritative status presentation and one action policy.
- A close action says whether work stops or continues.
- Destructive state is cleared only after persistence succeeds.
- Permission denial is nonfatal to unrelated capture groups and never masquerades as success.
- Every window-scoped completion must still own its request or task identity; an app-lifetime deletion completion must still match the in-flight profile.

## Root causes and corrections

| Area | Root cause | Correction and regression boundary |
| --- | --- | --- |
| Tray horizontal shift | `synchronizeViewport(_:)` rewrote the frame and bounds of the wrapper that an attached `NSPopover` had already positioned around its arrow/chrome. Resetting the wrapper origin shifted the full SwiftUI surface. | AppKit retains wrapper frame ownership. The app changes `popover.contentSize`, then maps only the hosted child to `container.bounds`. A genuine native `NSPopover.show(...)` test opens three times with a nonzero wrapper origin and verifies that the origin is preserved and the host remains centered. |
| Settings/workflow frame drift | Default `NSHostingController` sizing could rewrite the persistent window as the SwiftUI root, state, or selected tab changed. A stored undersized frame and a runtime-weakened minimum could survive or reappear. | Both hosting controllers disable intrinsic window sizing. Presentation repairs undersized content, reasserts a static minimum, and `windowWillResize` clamps the converted native frame on each axis while preserving valid user sizes. |
| Crowded or misleading flow | Capture partial/failure information could appear twice; a close glyph quit the app; some permission and terminal states exposed misleading or redundant actions; large text could escape a static tray body. | One status source is selected per state, Quit uses a power icon, action titles match behavior, authorized/denied location paths are explicit, and accessibility text uses the scrollable tray body. English and Korean catalogs and exact-copy tests cover new strings. |
| Stale async UI | A cancelled or closed task could clear a replacement task, reanimate a workflow after a late save, or lose the state of an in-flight deletion. | Window-scoped work uses per-request UUID/generation ownership, explicit invalidation, and one-at-a-time destination handoff. Deletion uses a profile-ID in-flight gate and clears UI state only after persistence succeeds. A fresh reopen owns a fresh window request, while an in-flight deletion intentionally survives tray close/reopen. |

## Installed verification

The installed bundle executable SHA-256 was `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305`.

| Surface | Installed result |
| --- | --- |
| Tray popover | The first through the 20th open used outer frame `394×342` and hosted viewport `368×316`. Both centers were `(1360, 202)` on every sample, for a horizontal and vertical center delta of `0 pt`. The original observed regression was a `-13 pt` horizontal delta. |
| Settings | Normal frame `900×568` survived 10 close/reopen cycles. An attempted `500×300` resize was immediately clamped to `680×480`; switching Profile → System at the minimum retained `680×480`. The read-only System status remained visible without clipping at the normal size. |
| Workflow | Initial native frame was `620×532`, corresponding to the intended `620×500` content area. An attempted `500×300` resize was immediately clamped to native frame `520×392`. Escape closed the review window without applying. |

Here, “first open” means the first measured tray open after reinstall while retaining the existing profile store and UserDefaults. It was not a clean first-ever launch or empty-store test. The 20 tray and 10 Settings sequence counts are operator-observed; committed images show endpoint and final states rather than every sample or input event.

The installed screenshots and a sanitized geometry/invariant record are in [the installed evidence set](evidence/ui-ux-installed-2026-07-17/README.md). Installed workflow screenshots were inspected locally but are not committed because they display live review values; committed workflow visuals use synthetic data.

## Deterministic verification

`make verify` passed the final source and package with 446 cases:

- 144 XCTest cases
- 301 Swift Testing cases across 38 suites
- 1 isolated genuine native-popover case

In local verification, running the genuine native-popover case concurrently with the offscreen AppKit suites produced a process-level crash after its assertions passed. The crash was not attributed to Swift Testing itself. The primary test script isolates that case as a stability workaround: it runs the rest of the suite in parallel, then runs the attached-native behavior test by itself. This preserves a real `NSPopover.show(...)` regression without making ordinary verification nondeterministic.

The same gate passed localization/policy lint, Swift Debug and Release, universal Xcode Debug and Release, Analyze, DMG/checksum creation, mounted metadata/resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID signature classification. The final DMG is `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`, SHA-256 `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`.

## Why earlier tests did not catch it

Earlier geometry fixtures proved SwiftUI containment in detached or synthetic hosts. They did not let a real `NSPopover` attach its wrapper to native arrow/chrome and assign a nonzero origin before the application synchronization path ran. Some checks also asserted configured size properties rather than the attached native frame after repeated presentation and resize. Window fixtures generally used a static root and therefore did not expose root replacement, tab changes, stale async completion, or an AppKit minimum that weakened after attachment.

The new boundary checks behavior at the point where ownership changes: attached native wrapper origin, persistent `NSWindow` frame, live resize delegate proposal, and request identity across close/reopen transitions.

## Safety invariants and remaining boundary

The installed pass used only tray open/close, window open/close, resize, tab selection, Escape, and the read-only status refresh. Profile-store and defaults hashes stayed unchanged; the pre-existing login-item registration-attempt count did not increase. Diagnostic Apply history was unchanged, and no new snapshot or hardware mutation was triggered.

This pass does not claim a full VoiceOver speech/rotor walkthrough, real macOS accessibility text-size walkthrough, physical Intel execution, quarantined Gatekeeper install, or hardware apply/rollback validation. The installed AX query identified the workflow window but could not independently prove the focused child control, so safe initial keyboard focus remains deterministic-policy tested rather than directly observed in the installed process.

## Deferred P2 cleanup

These are intentionally outside the P0/P1 correction and remain candidates for a later simplification pass:

- Consider making Capture a labeled primary empty-tray call to action instead of an icon-only header action.
- Re-evaluate Duplicate, Reorder, Import, and Export hierarchy and dirty-draft Export semantics.
- Clarify the meaning of per-group Included toggles.
- Complete VoiceOver review of `DisclosureGroup` content and keyboard behavior.
- Reconcile Advanced Diagnostics' `700 pt` minimum with the Settings window's `680 pt` minimum.
- Add minimum-size and accessibility fixtures for About, safety-confirmation, and result surfaces.
- Verify Command-, tab routing and generic storage-error prominence.
