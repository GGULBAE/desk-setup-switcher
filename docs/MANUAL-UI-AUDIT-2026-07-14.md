# Manual UI Audit — 2026-07-14

This report records the final-source synthetic render and read-only accessibility inspection for Desk Setup Switcher. The editor captures were refreshed after an installed-app screenshot exposed `Form` row compression around the Audio inclusion switches. It separates what the evidence proves from interactions and hardware behavior that remain pending.

## Safety boundary

The audit host exists only in `DEBUG` builds and requires `DESK_SETUP_UI_AUDIT=1`. It uses deterministic synthetic profiles and results, a process-specific temporary `ProfileStore`, an empty snapshot coordinator and apply registry, and no diagnostic store. Location permission requests are disabled without creating a live `CLLocationManager`. The model blocks public capture, apply, save, profile-storage, login-item, diagnostic, and readiness actions before they can reach injected dependencies. `UIAuditSafetyTests` deterministically verifies that those public actions produce no adapter, condition-reader, temporary-store, diagnostic-log, login-item, UserDefaults, or Core Location request invocation.

The images were captured from the current Xcode `Debug` app bundle, not the SwiftPM command-line executable, so SwiftUI main-bundle localization is represented. Screenshots used the audit window ID. AX logs were produced by reading attributes, children, and available action names. No AX action, AppleScript, `AXPress`, UI automation, mouse event, or keyboard event was executed.

Logical sizes below are the audit configuration's content targets. PNG pixel dimensions include Retina scaling and window chrome. The captured window alpha was composited onto opaque white without scaling so the evidence renders consistently across viewers; window shadows are omitted. The overview host sizes itself vertically to its localized content.

## Evidence

| # | Screen | Language/state | Logical size | PNG | Read-only AX log | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Menu overview | English, standard | 368×656 fitted | [PNG](evidence/manual-ui-audit-2026-07-14/01-overview-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/01-overview-en-standard.ax.txt) | Pass: long profile names, Ready/Partial text, primary actions, capture summary, and apply summary are visible without clipping. |
| 2 | Menu overview | Korean, standard | 368×648 fitted | [PNG](evidence/manual-ui-audit-2026-07-14/02-overview-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/02-overview-ko-standard.ax.txt) | Pass: Korean controls, states, counts, and result copy fit; synthetic profile names remain intentionally language-neutral fixture data. |
| 3 | Profile editor | English, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/03-editor-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/03-editor-en-standard.ax.txt) | Pass: selection, metadata, expanded Audio/default-input/default-output rows, fixed action bar, storage status, and import/export controls are visible. Category/option titles and compact Include controls retain their intended widths. Each profile row appears once in AX with a combined name/state description. |
| 4 | Profile editor | Korean, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/04-editor-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/04-editor-ko-standard.ax.txt) | Pass: Korean Audio, default-input, and default-output titles stay on readable lines beside their Include controls instead of collapsing into narrow vertical text. Tabs, status, action bar, and storage text also fit; profile-row AX duplication is absent. |
| 5 | Profile editor | Korean, minimum | 680×480 | [PNG](evidence/manual-ui-audit-2026-07-14/05-editor-ko-minimum.png) | [AX](evidence/manual-ui-audit-2026-07-14/05-editor-ko-minimum.ax.txt) | Pass for static layout: the compact vertical workspace has no visible horizontal clipping or overlap between editor, fixed action bar, storage status, and import/export controls. |
| 6 | Profile editor | English, simulated `.accessibility3` | 1100×820 | [PNG](evidence/manual-ui-audit-2026-07-14/06-editor-en-large-text.png) | [AX](evidence/manual-ui-audit-2026-07-14/06-editor-en-large-text.ax.txt) | Pass for simulated SwiftUI environment: larger text, sidebar wrapping, disclosures, scrolling, and fixed actions remain legible. This is not evidence of the real macOS text-size setting. |
| 7 | Validation | English, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/07-validation-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/07-validation-en-standard.ax.txt) | Pass: non-color error icon/text, summary, first issue, and field-reveal action are exposed. |
| 8 | Validation | Korean, standard | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/08-validation-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/08-validation-ko-standard.ax.txt) | Pass: Korean validation heading, error explanation, issue, and action metadata fit. |
| 9 | Permissions | English, denied synthetic state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/09-permissions-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/09-permissions-en-standard.ax.txt) | Pass for presentation: desired/effective login states and denied Location explanation/action are visible. No SMAppService or TCC request was made. |
| 10 | Permissions | Korean, denied synthetic state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/10-permissions-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/10-permissions-ko-standard.ax.txt) | Pass for presentation: Korean mismatch guidance and Location explanation/action fit. No SMAppService or TCC request was made. |
| 11 | Diagnostics | English, synthetic disabled state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/11-diagnostics-en-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/11-diagnostics-en-standard.ax.txt) | Pass: audit/system-access status, privacy claims, empty readiness facts, disclosures, and scrolling are visible. |
| 12 | Diagnostics | Korean, synthetic disabled state | 980×720 | [PNG](evidence/manual-ui-audit-2026-07-14/12-diagnostics-ko-standard.png) | [AX](evidence/manual-ui-audit-2026-07-14/12-diagnostics-ko-standard.ax.txt) | Pass: Korean status, readiness labels, empty counts, disclosures, and scrolling are visible. |

All 12 PNGs were visually inspected, including the corrected bilingual Audio-row alignment. All 12 AX logs are nonempty and localized as intended; each visible Include label maps to one named checkbox rather than a duplicate accessibility element. A text/AX and local Vision OCR scan found no user name, home path, email address, IP address, MAC address, UUID, credential, secret, or token. `Synthetic Studio` is a reserved synthetic fixture name; no real SSID or device identifier is present.

## Responsive-layout acceptance

The profile workspace intentionally uses a fixed responsive breakpoint at 760 points: a horizontal sidebar/editor layout above the breakpoint and a vertical sidebar/editor layout below it. `AnyLayout` keeps the same sidebar and editor identities across that transition. This replaces the former user-draggable `HSplitView`; a draggable divider is not part of the current accepted UX. The static 680×480 evidence proves the compact layout fits without visible horizontal clipping or lower-control overlap.

The required same-window 980→680→980 interaction still needs an explicit user result. Until that is supplied, preservation of the selected profile, expanded group/option, unsaved value, and focus across the live resize remains **pending**, even though the view identity is preserved in source. The actual MenuBarExtra Settings gear open/close/reopen path also remains **pending** because no user result was received; no UI automation was substituted.

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
