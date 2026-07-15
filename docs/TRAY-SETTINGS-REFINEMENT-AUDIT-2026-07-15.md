# Tray and Settings refinement audit — 2026-07-15

## Scope and safety boundary

This follow-up fixes the tray reopen offset, makes Settings and workflow destinations persistent and reopenable, derives the status-item icon/name from fresh profile state, and narrows profile editing to Display, Audio, and Network. Automated work used synthetic models and injected adapters only. It did not install or launch a packaged app, click the real status item, request permission, inspect personal hardware, or mutate display, audio, or network state.

## Implemented contracts

### Reopen root cause

The previous controller set the popover size and hosting frame only before `show`. During attachment, `NSPopover` can reparent the hosting view while `NSHostingController` fitting-size behavior and the prior scroll session still retain a displaced frame/bounds origin. A later open therefore had no explicit boundary that restored zero-origin AppKit geometry or the SwiftUI top anchor. The regression test reproduces that failure by corrupting the host origin on every show. The fix disables automatic hosting sizing, reasserts the same fixed viewport before and after attachment, verifies zero safe-area inset, and emits one generation-tagged top-scroll request; it does not calculate a compensating offset.

- Every tray open reasserts one fixed popover viewport and resets both hosting `frame` and `bounds` to zero origin before and after AppKit attaches the content window. Each generation requests a top scroll anchor. Twenty synthetic reopen cycles cover deliberately corrupted prior origins.
- Settings and workflow window controllers survive red-close by ordering out their existing window/root graph. Presentation activates the app first, deminiaturizes when needed, coalesces concurrent requests, and waits for visible/key state before tray dismissal. Ten-cycle tests cover Settings, Profile Editor, and workflow reuse.
- The status item uses the active applying profile first, otherwise a selected fresh zero-operation match, otherwise the generic fallback. It reuses one variable-length status item, validates the SF Symbol, limits the displayed profile name, and exposes tooltip/accessibility status. Historical `lastApplication` alone is never treated as a current match.
- The profile header contains name, icon, and enabled state on one row. Description and legacy input/system-output/mute/DNS/proxy/raw-position controls are hidden; their values round-trip but normalization makes them dormant.
- Display exposes extended/mirrored output, primary/secondary role, and per-display resolution/refresh rate. It labels the current public Core Graphics color-space name as read-only session evidence—not a ColorSync profile, HDR mode, or pixel encoding—and reports the unavailable apply/rollback capability instead of offering a false control.
- Audio exposes default input/output devices and input/output software volume. Input volume has typed snapshot, validation, planning, application, rollback, and unsupported/read-only omission behavior through Core Audio.
- Network stores Ethernet/Wi-Fi IPv4 values against a portable public identity made from service kind, service name, and interface type rather than a runtime service ID or BSD name. DHCP/manual values validate, but editing/apply remains disabled until an authorized rollback-safe implementation exists. Wi-Fi selection uses the current public CoreWLAN saved-network catalog, never an arbitrary password field. Identity ambiguity is nonfatal and does not remove unrelated Wi-Fi work.

## Detached visual evidence

The production profile editor was hosted in a detached `NSHostingView` at 2× scale using 980×720 standard/large-text and 680×480 minimum viewports. A short run-loop drain lets the synthetic `onAppear` draft initialization settle before pixels are cached. Each PNG has same-basename metadata recording the synthetic source, language, viewport, display mode, variant, no-live-mutation boundary, and detached accessibility limitation. The preceding 12-fixture tray matrix was also regenerated from the current source so its 0/1/3/10 profiles, long Korean, large text, dark, deletion, permission, and result states include the new Quit icon.

| Fixture | Coverage | Result |
| --- | --- | --- |
| [Display, English light](evidence/tray-settings-refinement-2026-07-15/13-display-en-light.png) | One-line profile header, output mode, primary display, primary/secondary role, resolution/refresh, color capability | Pass |
| [Audio, Korean light](evidence/tray-settings-refinement-2026-07-15/14-audio-ko-light.png) | Korean group/device labels, input/output devices, writable input-volume slider and numeric cue | Pass with detached-host localization boundary below |
| [Network, English dark](evidence/tray-settings-refinement-2026-07-15/15-network-en-dark.png) | Ethernet/Wi-Fi sections, service-specific DHCP presentation, disabled non-color capability reason, dark appearance | Pass |
| [Profile row, Korean minimum](evidence/tray-settings-refinement-2026-07-15/16-profile-ko-minimum.png) | 680×480 narrow layout, adaptive metadata row, Korean labels, fixed footer | Pass with detached-host localization boundary below |
| [Audio, English large text](evidence/tray-settings-refinement-2026-07-15/17-audio-en-large-text.png) | Accessibility-3 text, metadata wrapping, Audio controls, non-color state | Pass |

The metadata/privacy scan contains no home path, password, secret, token, real SSID, personal IP address, location, serial, or device UID. Synthetic service/device names are intentionally non-personal. Detached SwiftUI localization does not force every native control label through the runtime language override, so the Korean image is evidence of layout and the app-localized content visible there, not a complete Korean linguistic audit. Exact runtime-bundle tests and catalog lint separately cover English/Korean key parity and values. Virtual SwiftUI accessibility children also require an onscreen host, so full VoiceOver is not claimed.

Evidence can be regenerated one fixture per test process to avoid AppKit detached-host cache artifacts:

```sh
DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 \
DESK_SETUP_REFINEMENT_EVIDENCE_FIXTURE=13-display-en-light \
DESK_SETUP_REFINEMENT_EVIDENCE_DIR="$PWD/docs/evidence/tray-settings-refinement-2026-07-15" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --filter rendersSimplifiedProfileSections
```

Repeat with `14-audio-ko-light`, `15-network-en-dark`, `16-profile-ko-minimum`, and `17-audio-en-large-text`. The refreshed tray matrix uses `DESK_SETUP_WRITE_TRAY_EVIDENCE=1` and `DESK_SETUP_TRAY_EVIDENCE_DIR="$PWD/docs/evidence/tray-surface-v2-2026-07-15"` with the `rendersSyntheticMatrix` test.

## Evidence boundary and manual follow-up

The deterministic suite proves ownership, ordering, model semantics, adapter behavior, localization structure, and detached layout. It does not prove the actual status-item width/icon in the macOS menu bar, native popover arrow/anchor/ghost-frame behavior, red-close/reopen first responder on an installed app, complete keyboard/VoiceOver navigation, actual ColorSync/HDR state, real microphone gain support, service matching after rename/hot-plug, TCC, or any live apply/rollback. This goal's safety boundary prohibited installation, so no package was copied to `/Applications` and no installed interaction was performed.

Pending manual checklist:

- [ ] Open/close the actual tray 20 times on one screen and confirm identical left/right inset, header origin, width, and top scroll.
- [ ] Red-close and reopen Settings ten times, then Profile Edit ten times; confirm the requested window is visible, key, and front while the tray is closed.
- [ ] Confirm `Cmd+,`, already-visible/non-key recovery, and an unsaved draft remain independent of tray lifetime.
- [ ] Observe matched, applying, deleted/failed, long-name, and fallback status-item icon/name states in the real menu bar.
- [ ] Complete English/Korean keyboard-only focus order, visible focus ring, non-color state, and VoiceOver speech/focus review.
- [ ] Run separately authorized hardware procedures only if display/audio/network mutation and rollback evidence is requested.

## Final non-live verification

`make verify` passed with every live environment flag unset: source/localization policy; 338 default cases (132 XCTest and 206 Swift Testing, six opt-in skips); Swift Debug/Release; universal Xcode Debug/Release; Xcode Analyze; DMG/checksum; mounted English/Korean resources; `x86_64 arm64`; and ad-hoc/no-Developer-ID signature classification. `git diff --check` passed separately. The verified local DMG SHA-256 is `539c203607782302799d68acdda2f64666f0ace5897fa325a79e1dfdcfc98f78`. No application install, launch, profile-store access, permission request, hardware read, setting mutation, push, or release occurred.
