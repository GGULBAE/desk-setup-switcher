# Tray Surface Architecture v2 audit — 2026-07-15

## Scope and safety boundary

This audit covers the production cutover from SwiftUI `MenuBarExtra(.window)` to app-owned `NSStatusItem` + `.applicationDefined` `NSPopover` + `NSHostingController`. All automated evidence is deterministic and non-live. It does not click the status item, show a window or popover, inject keyboard/mouse events, request TCC, read hardware, write Keychain, open System Settings, access the profile store, apply a profile, or mutate display/audio/network/input settings.

The detached renderer hosts the production `TrayRootView` in an `NSHostingView` with synthetic models. A neutral white/black background is added only to make transparent SwiftUI content readable in PNGs; production leaves full-surface material/chrome to `NSPopover`. The PNGs therefore prove contained layout, not the native arrow, anchor, shadow, material, or absence of a ghost frame.

## Automated contracts

- Ownership: factories verify one status item wrapper, one `.applicationDefined` popover wrapper, and one hosting controller with viewport-matching bounds.
- Geometry: 0, 1, 3, and 10-profile sizes, small-screen clamping, scale-factor invariance, screen-change-on-next-open, and immutable open-session viewport all pass.
- Routing: every `TrayAction` has one disposition; stay-open actions cannot close/order out; destination close occurs only after visible/key; failure/cancel stays reachable; identical double-clicks coalesce; stale generations cannot close a reopened tray; only Quit terminates.
- Lifetime: deletion/focus and capture tasks survive dismiss/reopen, duplicate capture is suppressed, and persistent Settings/workflow windows retain their content window.
- Accessibility/localization: icon labels/help, non-color status copy, deterministic delete focus transitions, and exact English/Korean runtime strings pass.
- Safety: synthetic public actions do not reach adapters, storage, diagnostics, login items, UserDefaults, or Core Location request closures.

## Detached visual evidence

Every PNG is 736 pixels wide, representing the 368-point tray at 2× scale. Empty and single-profile fixtures use their deterministic 300- and 350-point viewport heights; compact/overflow fixtures use the 560-point cap.

| # | Fixture | Coverage | Result |
| --- | --- | --- | --- |
| 01 | [empty English light](evidence/tray-surface-v2-2026-07-15/01-empty-en-light.png) | Empty state, header actions, compact height | Pass |
| 02 | [single English light](evidence/tray-surface-v2-2026-07-15/02-single-en-light.png) | One profile, state-aware actions | Pass |
| 03 | [three English light](evidence/tray-surface-v2-2026-07-15/03-three-en-light.png) | Compact list and cap | Pass |
| 04 | [overflow English light](evidence/tray-surface-v2-2026-07-15/04-overflow-en-light.png) | Ten profiles and internal scrolling content | Pass |
| 05 | [delete English light](evidence/tray-surface-v2-2026-07-15/05-delete-en-light.png) | Complete inline destructive confirmation | Pass |
| 06 | [permission English light](evidence/tray-surface-v2-2026-07-15/06-capture-permission-en-light.png) | Actionable permission handoff state | Pass |
| 07 | [capture success English dark](evidence/tray-surface-v2-2026-07-15/07-capture-success-en-dark.png) | Success banner and dark appearance | Pass |
| 08 | [capture failure English high contrast](evidence/tray-surface-v2-2026-07-15/08-capture-failure-en-light.png) | Failure banner and AppKit high-contrast Aqua | Pass |
| 09 | [apply result English dark](evidence/tray-surface-v2-2026-07-15/09-apply-result-en-dark.png) | Compact result and detail handoff | Pass |
| 10 | [overflow Korean light](evidence/tray-surface-v2-2026-07-15/10-overflow-ko-light.png) | Korean long-list wrapping | Pass |
| 11 | [delete Korean dark](evidence/tray-surface-v2-2026-07-15/11-delete-ko-dark.png) | Korean destructive state and dark appearance | Pass |
| 12 | [overflow Korean large text](evidence/tray-surface-v2-2026-07-15/12-overflow-ko-large-text.png) | Korean `.accessibility3`, wrapping, capped viewport | Pass |

Each PNG has a same-basename `.ax.txt` metadata file. The files record fixture language, viewport, profile count, full-surface-background policy, declared icon labels, applied high-contrast appearance, and the detached-host limitation. A privacy scan found no home path, password/secret/token, SSID, exact location, network address, or personal device identifier.

Detached `NSHostingView` exposes only its root `AXGroup`; virtual SwiftUI children require an onscreen accessibility host. The metadata says so and does not claim a complete accessibility tree. Reduce Transparency is a read-only SwiftUI environment value in this detached setup: fixtures 09 and 12 record that it was requested but not applied. Large text is injected through `.accessibility3`; fixture 08 applies AppKit's accessibility high-contrast Aqua appearance.

The evidence can be regenerated without live access:

```sh
DESK_SETUP_WRITE_TRAY_EVIDENCE=1 \
DESK_SETUP_TRAY_EVIDENCE_DIR="$PWD/docs/evidence/tray-surface-v2-2026-07-15" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter TrayOffscreenEvidenceTests
```

## Package and test result

Non-live `make verify` passed on 2026-07-15 with 326 default cases: 130 XCTest cases and 196 Swift Testing cases, six opt-in skips, and zero failures. It also passed formatting/source policy, English/Korean catalog validation, Swift Debug/Release, universal Xcode Debug/Release, Xcode Analyze, DMG creation/checksum, mounted metadata/resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID signature classification.

Tray Surface v2 baseline DMG SHA-256: `2e5248175e8c68810bd17abf52da30356ff9ccee7cd167d97ac3b815e3b04127`.

The package was not installed, launched, pushed, or submitted to CI. Earlier installed interactions in [MANUAL-UI-AUDIT-2026-07-14.md](MANUAL-UI-AUDIT-2026-07-14.md) used `MenuBarExtra` and are not v2 interaction evidence.

## Required manual follow-up

The following remain unchecked:

- actual status-item click/toggle and popover anchor/arrow/material/shadow/ghost-frame behavior;
- outside-click, app-deactivation, Esc, and reopen timing under native AppKit presentation;
- visible/key destination ordering and first responder for Settings, permission, dirty-draft, preview, confirmation, and result workflows;
- complete keyboard-only traversal, focus rings, VoiceOver speech/rotor/focus, and deletion focus recovery;
- real Light/Dark, Increase Contrast, Reduce Transparency, and macOS text-size settings;
- multi-display and scale-factor changes between open sessions;
- TCC denial/grant, login-item approval/retry/reboot, import/export, Gatekeeper/quarantine, physical Intel, live Keychain, and every mutation/rollback procedure.

The next implementation task is **tray detailed UI refinement**. It must preserve the fixed open-session viewport, single scroll region, typed action dispositions, and app-lifetime workflow ownership established here.
