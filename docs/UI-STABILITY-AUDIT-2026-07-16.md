# Tray, Settings, and workflow UI stability audit — 2026-07-16

## Scope and safety boundary

This audit covers the tray popover, profile Settings workspace, apply preview, protected-change confirmation, and persistent destination-window lifecycle. It was prompted by three installed-build screenshots showing an empty tray that appeared displaced, an apply preview that did not visibly advance, and a refreshed preview whose body appeared to retain the wrong scroll position.

The user-provided references are preserved as [empty tray](evidence/ui-stability-audit-2026-07-16/01-user-empty-tray-ko.png), [apply preview](evidence/ui-stability-audit-2026-07-16/02-user-apply-preview-ko.png), and [refreshed preview](evidence/ui-stability-audit-2026-07-16/03-user-refresh-preview-ko.png). All implementation and automated verification used synthetic profiles, injected adapters, and attached/offscreen AppKit hosts. No display, ColorSync, audio, network, mouse, keyboard, TCC, Keychain, or real profile setting was changed.

## Journey audit

| Step | Health before | Finding | Current correction |
| --- | --- | --- | --- |
| 1. Open the tray | Needs improvement | Every open began a readiness refresh. While the cached match was still valid, the status item temporarily changed from profile-name width to icon-only width. Because that same button anchors the popover, the anchor itself could move. | Cached readiness remains usable during refresh. Duplicate status presentations are ignored, and any title/width change is coalesced until the popover has closed. |
| 2. View an empty or first-profile tray | Needs improvement | The empty state lived inside the same always-present scroll view as cards and transient notices. English header copy also wrapped because the text Capture button competed with the title. A single profile used a taller viewport than the empty state and left a large unused tail. | Truly empty idle content is a centered, non-scrolling body. Capture is icon-only with an explicit accessibility label/help, the title is one line, and empty/first-profile states share the same 260-point viewport. |
| 3. Reopen or change tray state | Needs improvement | Scroll correction happened only after AppKit had shown and attached the popover, and focus scrolling used a visible animation. A persistent scroll view could briefly expose its previous offset. | Each open generation owns a new scroll identity with a top default. Attachment still has a guarded top request, but focus moves without animation and bounce appears only when content actually exceeds the viewport. |
| 4. Resize or reopen Settings | Broken at minimum size | At exactly 760 points the whole workspace switched between horizontal and vertical anatomy. The real window can be 680 points wide and adds outer TabView padding, so ordinary resizing could move the entire sidebar above the editor. Dynamic footer/status rows also changed the editor viewport height. | Every supported window width keeps one horizontal anatomy: a fixed 210-point sidebar, divider, and editor with a 390-point minimum. Footer and save/revert bars are single fixed-height rows with truncation/help rather than structural wrapping. |
| 5. Edit or switch profiles | Needs improvement | `LazyVStack`, repeated identical `@Published` assignments, conditional validation summary insertion, live snapshot replacement, and a persistent scroll offset could all reflow the hierarchy while typing or carry one profile's deep position into another. | The editor uses a deterministic `VStack`, suppresses identical session/activity publications, and shows the large validation summary after an enabled Save attempt while still blocking invalid persistence. Invalid-field accessibility metadata keeps one view hierarchy so focus/caret survives validation changes. The runtime catalog adopts at most the first completed refresh in a presentation and then remains fixed until reopening. Scroll identity changes only for a different profile or a hidden-window reopen; invoking an already-visible Settings window preserves it. |
| 6. Review and refresh an apply plan | Needs improvement | A persistent preview scroll view had no request identity. When preflight correctly returned a new refreshed request, the orange notice could be inserted while the body retained the prior offset, making the update look like a partial or ineffective transition. Workflow child screens also declared conflicting minimum/ideal sizes. | The preview scroll view is keyed by `PendingApplyRequest.id`, defaults to top, and uses size-based bounce. Notices and operations share that scroll region above a fixed footer, including at 520×360 with simulated large text. Workflow screens fill one persistent window canvas instead of requesting different child sizes. Korean now includes the previously missing “Change input volume” translation. |
| 7. Confirm protected changes | At risk with long content | The countdown used proportional digits and an unbounded list of change summaries inside a fixed 340-point view. | Countdown digits are monospaced. Dynamic summaries own a bounded internal scroll region while the confirmation fills the stable workflow canvas. |

## Visible comparison

The original English empty evidence wrapped the product name and exposed a text Capture button: [before](evidence/ui-stability-audit-2026-07-16/baseline-tray/01-empty-en-light.png). The current synthetic frame keeps the header on one line and centers a non-scrolling empty body: [after, English](evidence/ui-stability-audit-2026-07-16/after-tray/01-empty-en-light.png) and [after, Korean](evidence/ui-stability-audit-2026-07-16/after-tray/01b-empty-ko-light.png).

The previous minimum Settings renderer switched to a tall stacked anatomy: [before](evidence/ui-stability-audit-2026-07-16/baseline-settings/16-profile-ko-minimum.png). The current full `RuntimeSettingsRoot` at the actual 680×480 minimum keeps sidebar, editor, fixed action bar, and footer in one stable structure: [after](evidence/ui-stability-audit-2026-07-16/after-settings/16-profile-ko-minimum.png). The default 900×568 view is recorded in [English](evidence/ui-stability-audit-2026-07-16/after-settings/13-display-en-light.png).

Apply workflow evidence records [initial English review](evidence/ui-stability-audit-2026-07-16/after-workflow/23-apply-preview-en-initial.png), [refreshed Korean review](evidence/ui-stability-audit-2026-07-16/after-workflow/24-apply-preview-ko-refreshed.png), and the [520×360 force/refreshed Korean large-text minimum](evidence/ui-stability-audit-2026-07-16/after-workflow/25-apply-preview-ko-minimum-large-text.png). Each begins at the explanatory notices and keeps Cancel/Apply fully visible in a fixed footer.

## Accessibility and localization

- Capture, Settings, Quit, destructive actions, validation errors, workflow status, and protected-change countdown retain explicit labels or hints and non-color symbols/text.
- Removing the focus-scroll animation avoids unnecessary motion during keyboard state changes.
- Invalid controls receive localized high-priority validation custom content. Valid controls retain the same modifier hierarchy with an empty value intended to remain silent, avoiding structural focus/caret churn and repeated “Valid” announcements; native VoiceOver confirmation remains manual.
- English/Korean catalogs remain parity checked; the missing “Change input volume” operation title was added in both languages.
- The attached offscreen Settings host now renders native `List` rows, unlike the previous detached-only host.

This is not a complete accessibility certification. Native VoiceOver speech/rotor order, full keyboard traversal, focus rings after real window activation, real Increase Contrast/Reduce Transparency settings, and installed large-text behavior remain manual.

## Deterministic regression coverage

Focused non-live verification currently passes 39 tests covering:

- a status-item spy whose anchor width changes with its title, proving the width stays frozen while the tray is open and the latest state applies after close;
- 20 reopen generations, stale attachment rejection, zero-origin recovery, fixed open-session geometry, asymmetric safe-area ownership, and empty-state raster centering;
- one stable horizontal Settings policy at the real minimum content width, refresh-completion-aware catalog updates, already-visible Settings preservation, 20 true reopen/profile presentations, reachable invalid-save feedback, and identical-draft publication suppression;
- attached/offscreen tray, full Settings-root, default apply-preview, refreshed apply-preview, and 520×360 large-text workflow evidence without live system mutation.

The integrated non-live `make verify` gate passes 375 default cases: 134 XCTest cases with five skipped opt-in cases and 241 Swift Testing cases with two disabled opt-in cases. Lint/localization, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and ad-hoc/no-Developer-ID classification all pass; `git diff --check` passes separately. The verified universal DMG SHA-256 is `516b968718aeb3c1c247e1a2deca7a28d45820d119f31ea992d4b475071f3638`. It replaced `/Applications/Desk Setup Switcher.app` through a staged copy with rollback protection and passed bundle identity, version 0.1.0, `x86_64 arm64`, signature, and mounted-source executable-equality checks. It was not launched and no live setting mutation ran.

## Evidence limits and remaining manual checks

Attached/offscreen screenshots prove contained layout, catalog parity, selected localization paths, and deterministic synthetic state. The forced Korean locale does not replace every SwiftUI/AppKit automatic-localization control in this host, so English Cancel/Profile/Icon/Save/Revert/Import/Export text in some frames is not claimed as a complete Korean render. These frames also do not prove the installed menu-bar anchor, popover arrow/material, a single-frame native flicker, outside-click timing, actual window ordering, or hardware effects. The black top-tab material sometimes captured by the offscreen `TabView` host is an AppKit raster-host limitation and is not treated as installed visual evidence.

The remaining high-value manual check is a user-driven installed pass: open/close the tray 20 times, inspect empty/one/overflow states, resize Settings 900→680→900, switch between a deeply scrolled profile and another profile, and confirm an initial→refreshed apply preview starts at the orange notice. Any actual Apply Profile confirmation that changes hardware remains a separate explicitly approved mutation-and-rollback procedure.
