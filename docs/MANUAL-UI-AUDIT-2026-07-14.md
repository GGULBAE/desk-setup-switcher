# Manual UI Audit — 2026-07-14

This report records a synthetic render and read-only accessibility inspection for Desk Setup Switcher at the source point captured below. That source added per-profile menu deletion controls, an expanded value-free explanation of partial captures, a card-based profile editor with more usable width, and a simplified Profiles/System/About information architecture. Later inline-delete and actionable capture-permission corrections are documented separately because they are not depicted in these images. Diagnostics remain available as an on-demand advanced sheet. The report separates what the evidence proves from interactions and hardware behavior that remain pending.

## Safety boundary

The audit host exists only in `DEBUG` builds and requires `DESK_SETUP_UI_AUDIT=1`. It uses deterministic synthetic profiles and results, a process-specific temporary `ProfileStore`, an empty snapshot coordinator and apply registry, and no diagnostic store. Location permission requests are disabled without creating a live `CLLocationManager`. The model blocks public capture, apply, save, profile-storage, login-item, diagnostic, and readiness actions before they can reach injected dependencies. `UIAuditSafetyTests` deterministically verifies that those public actions produce no adapter, condition-reader, temporary-store, diagnostic-log, login-item, UserDefaults, or Core Location request invocation.

The images were captured from the current Xcode `Debug` app bundle, not the SwiftPM command-line executable, so SwiftUI main-bundle localization is represented. Screenshots used the audit window ID. AX logs were produced by reading attributes, children, and available action names. No AX action, AppleScript, `AXPress`, UI automation, mouse event, or keyboard event was executed.

Logical sizes below are the audit configuration's content targets. PNG pixel dimensions include Retina scaling and window chrome. The captured window alpha was composited onto opaque white without scaling so the evidence renders consistently across viewers; window shadows are omitted. The overview host sizes itself vertically to its localized content.

## Evidence

| # | Screen | Language/state | Logical size | PNG | Read-only AX log | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Menu overview | English, standard | 368×845 fitted | [PNG](evidence/manual-ui-audit-2026-07-14/01-overview-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/01-overview-en-standard.ax.txt) | Pass: each profile has a named delete button, long names and primary actions fit, and the audit-only expanded partial-capture explanation identifies snapshot-only, unreadable, and unsupported items without captured values. |
| 2 | Menu overview | Korean, standard | 368×824 fitted | [PNG](evidence/manual-ui-audit-2026-07-14/02-overview-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/02-overview-ko-standard.ax.txt) | Pass: Korean delete controls, states, counts, item names, explanations, and result copy fit; synthetic profile names remain intentionally language-neutral fixture data. |
| 3 | Profile editor | English, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/03-editor-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/03-editor-en-standard.ax.txt) | Pass: the narrower fixed sidebar leaves more editor width; metadata, category cards, expanded Audio/default-input content, fixed action bar, storage status, and import/export controls are visible. Each profile row appears once in AX with a combined name/state description. |
| 4 | Profile editor | Korean, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/04-editor-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/04-editor-ko-standard.ax.txt) | Pass: Korean Audio and default-input titles stay on readable lines beside regular-size Include controls. Card spacing, tabs, status, action bar, and storage text fit; profile-row AX duplication is absent. |
| 5 | Profile editor | Korean, minimum | 680×480 | [PNG](evidence/manual-ui-audit-2026-07-14/05-editor-ko-minimum.png) | [AX](evidence/manual-ui-audit-2026-07-14/05-editor-ko-minimum.ax.txt) | Pass for static layout: the compact vertical workspace has no visible horizontal clipping or overlap between editor, fixed action bar, storage status, and import/export controls. |
| 6 | Profile editor | English, simulated `.accessibility3` | 1100×820 | [PNG](evidence/manual-ui-audit-2026-07-14/06-editor-en-large-text.png) | [AX](evidence/manual-ui-audit-2026-07-14/06-editor-en-large-text.ax.txt) | Pass for simulated SwiftUI environment: larger text, sidebar wrapping, disclosures, scrolling, and fixed actions remain legible. This is not evidence of the real macOS text-size setting. |
| 7 | Validation | English, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/07-validation-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/07-validation-en-standard.ax.txt) | Pass: non-color error icon/text, summary, first issue, and field-reveal action are exposed. |
| 8 | Validation | Korean, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/08-validation-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/08-validation-ko-standard.ax.txt) | Pass: Korean validation heading, error explanation, issue, and action metadata fit. |
| 9 | System | English, denied synthetic state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/09-permissions-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/09-permissions-en-standard.ax.txt) | Pass for presentation: the reduced three-tab navigation, login state, denied Location explanation/action, and secondary troubleshooting entry are visible. No SMAppService or TCC request was made. |
| 10 | System | Korean, denied synthetic state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/10-permissions-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/10-permissions-ko-standard.ax.txt) | Pass for presentation: Korean login/permission guidance and the advanced-diagnostics entry fit. No SMAppService or TCC request was made. |
| 11 | Advanced diagnostics sheet | English, synthetic disabled state | 700×680 | [PNG](evidence/manual-ui-audit-2026-07-14/11-diagnostics-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/11-diagnostics-en-standard.ax.txt) | Pass: the on-demand sheet exposes audit/system-access status, privacy claims, empty readiness facts, disclosures, scrolling, and a keyboard-close action. |
| 12 | Advanced diagnostics sheet | Korean, synthetic disabled state | 700×680 | [PNG](evidence/manual-ui-audit-2026-07-14/12-diagnostics-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/12-diagnostics-ko-standard.ax.txt) | Pass: Korean status, readiness labels, empty counts, disclosures, scrolling, and 완료 action are visible. |

All 12 PNGs were visually inspected, including the bilingual menu explanations, delete controls, card-based editor, reduced tab set, and advanced-diagnostics sheet. All 12 AX logs are nonempty and localized as intended; each visible Include label maps to one named checkbox rather than a duplicate accessibility element. A text/AX scan found no user name, home path, email address, IP address, MAC address, UUID, credential, secret, or token. The ordinary disabled application-menu item named `Passwords…` is not captured user data. `Synthetic Studio` is a reserved synthetic fixture name; no real SSID or device identifier is present.

## Responsive-layout acceptance

The profile workspace intentionally uses a fixed responsive breakpoint at 760 points: a horizontal sidebar/editor layout above the breakpoint and a vertical sidebar/editor layout below it. `AnyLayout` keeps the same sidebar and editor identities across that transition. This replaces the former user-draggable `HSplitView`; a draggable divider is not part of the current accepted UX. The static 680×480 evidence proves the compact layout fits without visible horizontal clipping or lower-control overlap.

The required same-window 980→680→980 interaction still needs an explicit user result. Until that is supplied, preservation of the selected profile, expanded group/option, unsaved value, and focus across the live resize remains **pending**, even though the view identity is preserved in source. The actual MenuBarExtra Settings gear open/close/reopen path also remains **pending** because no user result was received; no UI automation was substituted.

The later inline-delete-confirmation correction is source/build verified but is not depicted in these 12 static captures. Its confirmation is deliberately part of the profile card rather than a system dialog, avoiding the observed MenuBarExtra dismissal, and its list viewport now reserves additional height while confirmation is open to avoid clipping either action. The later capture-permission correction is also absent: current source explains and requests undetermined Location access, routes denied access to macOS System Settings or an explicit Wi-Fi-free path, and omits snapshot-only/unreadable/unsupported noise from the result card. Injected tests cover these actions without live TCC mutation. User-driven delete and TCC click-throughs remain the appropriate final interaction checks.

## Current capture-permission click-through

This check is intentionally user-driven. Do not use UI automation, AX actions, AppleScript, or an automated TCC reset. Start from the installed package with DMG SHA-256 `8760d68754f3bc1eebca37319bd0d2bfc29b6b3d90832532e0a64cd072506a9b`. Record only pass/fail and visible generic state text; do not record or screenshot an actual SSID, IP address, location, or device identifier.

1. Record the current Desk Setup Switcher Location permission so it can be restored afterward.
2. If the app is already denied or restricted, select **Capture**. Confirm that the explanation offers **Open macOS System Settings**, **Capture Without Wi-Fi**, and **Cancel** without displaying a Wi-Fi name.
3. Select **Capture Without Wi-Fi**. Confirm that applicable settings are captured and that snapshot-only, unreadable, unsupported, and network-service-order categories do not appear as partial-capture errors.
4. Repeat **Capture**, then select **Open macOS System Settings**. Confirm that System Settings opens; navigate manually to Privacy & Security > Location Services. The app deliberately uses the public application-open path rather than a private preference-pane URL.
5. Grant Location access, return to the app, and select **Capture** again. When Wi-Fi is connected and macOS exposes its name, confirm that the current Wi-Fi option can be captured and no permission-needed card remains. A disconnected interface or a still-hidden name must remain nonfatal and must not block unrelated settings.
6. On a clean account where authorization is genuinely **Not Determined**, select **Capture**, verify the app's purpose explanation appears before the macOS prompt, then choose the intended macOS response. If this Mac is already determined, record this branch as not run instead of resetting TCC automatically.
7. Restore the original Location permission. Delete any temporary profile through the app if it is no longer needed.

This read-only capture check must not apply a profile or change display, audio, network, mouse, or keyboard settings. Completing only the denied branch does not prove the first-request prompt or granted Wi-Fi behavior; record each branch independently.

## Evidence boundary and pending checks

The synthetic host is evidence for the contained SwiftUI content only. It does not prove the actual MenuBarExtra chrome, status-item anchor, or menu placement. The optional DEBUG-only synthetic MenuBarExtra path suppresses production dependencies, but its gear-button click and Settings reactivation require a user's direct click.

The following remain separate evidence and are not marked complete here:

- complete keyboard-only traversal and focus order;
- VoiceOver speech, rotor behavior, and focus movement;
- real macOS text-size/accessibility settings (`.accessibility3` here is simulation only);
- contrast/transparency under other system appearance settings;
- actual TCC denial/grant prompts and Wi-Fi-name behavior;
- real SMAppService approval/failure/retry, login-at-boot, and reboot persistence;
- Keychain writes;
- quarantined download and Gatekeeper flow;
- physical Intel execution;
- import/export manual flow;
- live display, audio, network, mouse, keyboard, apply, confirmation, mutation, and rollback behavior.
