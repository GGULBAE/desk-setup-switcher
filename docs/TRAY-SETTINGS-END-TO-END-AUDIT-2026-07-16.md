# Tray/settings end-to-end audit — 2026-07-16

## Scope and safety boundary

This audit records the deterministic P0→P1→P2 tray/settings implementation. All automated work used synthetic profiles, injected system APIs, detached `NSHostingView` rendering, and non-live build/package commands. No display, ColorSync, audio, network, mouse, or keyboard setting was changed. No authorization prompt, TCC action, Keychain write, installation, launch of the packaged app, UI automation, push, tag, signing/notarization, or publication occurred.

Mock/offscreen evidence proves code paths and contained layout only. It does not prove an installed status-item anchor, native window ordering, real authorization UI, hardware behavior, perceived audio/display output, connectivity preservation, or rollback on a physical Mac.

## P0 — deterministic tray attachment

`TrayGeometry` uses a 368-point width and explicit height tiers: 260 for zero profiles, 300 for one, 316 for two, and 560 for three or more. The SwiftUI root owns one symmetric 16-point horizontal inset and ignores native horizontal safe-area values, preventing a second asymmetric inset. A two-profile regression bounds the unused space below its cards.

`TrayPopoverController` records the first-attach stages `beforeShow`, `showReturned`, `contentWindowAttached`, `firstLayoutCompleted`, `didBecomeKey`, and `finalViewportSynchronized`. It resets host origin before show, attaches after the popover returns, performs one generation-guarded first-layout completion, and allows one final viewport synchronization. There is no sleep or delayed corrective resize. Stale completions cannot mutate a later generation. Deterministic tests cover late layout, displaced bounds, asymmetric safe area, stale attachment, and 20 reopen generations.

## P1 — one direct product model

- Profile activation is no longer a product concept. Legacy `isEnabled == false` remains decodable, normalizes to true, is ignored by dirty comparison, does not filter tray/settings, and cannot reject apply.
- Display, Audio, and Network are flat and always expanded. Each visible leaf owns Include; there is no group or option disclosure state.
- The visible surface omits unsupported, read-only, future, or ambiguous controls. It does not render a disabled promise.
- Description, conditions, Input, display origin/rotation/active state, audio system-output/mute, Wi‑Fi power/SSID, global IPv4, DNS, and proxies remain round-trip compatible but normalize dormant.
- Capture summaries, profile summaries, validation, and apply results include only the current visible contract.

## P2 — visible means working end to end

`VisibleSettingRegistry` declares nine visible setting kinds. Every contract contains capture, edit, validate, plan, apply, verify, and rollback stages plus runtime-catalog, localization, and accessibility metadata.

| Group | Visible setting | Runtime evidence | Apply/read-back/rollback contract |
| --- | --- | --- | --- |
| Display | Output mode | Current Core Graphics topology and mode catalog | Atomic app-only topology; exact current topology read-back; complete prior topology rollback |
| Display | Primary display | Stable display identity and current topology | Same atomic topology operation and rollback |
| Display | Resolution/refresh | Per-display supported-mode catalog | Exact logical/pixel dimensions with refresh tolerance; complete topology rollback |
| Display | ColorSync ICC profile | Per-display public ColorSync catalog with registered ID and ICC SHA-256 | Resolve one current runtime URL, apply public mapping, exact target read-back, previous mapping rollback |
| Audio | Default input | Core Audio device UID catalog | Switch UID, re-read default, restore prior UID |
| Audio | Default output | Core Audio device UID catalog | Switch UID, re-read default, restore prior UID |
| Audio | Input volume | Settable input-volume catalog for resolved default input UID | Scalar apply/read-back tolerance, prior scalar rollback |
| Audio | Output volume | Settable output-volume catalog for resolved default output UID | Scalar apply/read-back tolerance, prior scalar rollback |
| Network | Service DHCP/manual IPv4 | Exactly one portable service identity plus exact serialized IPv4 rollback dictionary | Authorized set/commit/apply, dynamic-store completion, exact read-back, exact dictionary rollback |

The end-to-end invariant test builds actual display, audio, and network adapters over synthetic APIs and asserts that every projected field validates, produces a real operation with rollback evidence, applies successfully, verifies through a fresh read, and restores the original state. Unsupported audio controls, unresolvable ColorSync rows, missing network rollback evidence, and ambiguous network identities project no control.

## Public API boundary

Display topology uses public Core Graphics configuration APIs and app-only temporary scope. Color selection means a ColorSync ICC device-profile mapping only; it does not mean HDR, pixel encoding, vendor picture mode, or an arbitrary “color mode.” Profile JSON stores registered profile ID, SHA-256 of ICC file bytes, and display name, never a runtime file URL. The implementation is aligned with Apple's public [`CGDisplayConfigRef`](https://developer.apple.com/documentation/coregraphics/cgdisplayconfigref), [`CGConfigureOption`](https://developer.apple.com/documentation/coregraphics/cgconfigureoption), [`kColorSyncDeviceDefaultProfileID`](https://developer.apple.com/documentation/colorsync/kcolorsyncdevicedefaultprofileid), and [`kColorSyncCustomProfiles`](https://developer.apple.com/documentation/colorsync/kcolorsynccustomprofiles) documentation.

Service IPv4 uses Authorization Services and public SystemConfiguration. The live adapter opens preferences with [`SCPreferencesCreateWithAuthorization`](https://developer.apple.com/documentation/systemconfiguration/scpreferencescreatewithauthorization%28_%3A_%3A_%3A_%3A%29), re-resolves one service/protocol, checks lock/set/commit/apply/unlock, waits for `SCDynamicStore` completion, and then performs exact DHCP/manual read-back. Deterministic tests cover an early notification and zero-timeout path without sleeping, plus authorization denial and each preferences/read-back failure. No real authorization request was made.

Core Audio switching is UID-based. A default-device operation sorts before volume, so volume resolves against the target device. Percent UI values convert exactly to/from normalized scalar values. Non-settable or missing device controls remain absent and do not degrade unrelated readiness.

## Protected high-risk ordering

The engine applies low-risk Audio first, then protected Display, then protected Network. Revert restores completed protected operations in reverse order, so connectivity returns before display rollback. The 15-second protected-change window lists affected groups and sanitized summaries. Keep confirms; Revert, timeout, confirmation failure, safety-window close, or app termination restores temporary state. Deterministic tests cover network-first protected rollback, failed confirmation, failed rollback reporting, one-shot tokens, close-triggered rollback, and termination deferral. No live timeout/quit/window-close rollback was run.

## Synthetic visual evidence

The following detached-host images were visually inspected. Their paired `.ax.txt` files record the synthetic host, language, viewport, variant, and the limitation that virtual SwiftUI children require an onscreen accessibility host for a complete native AX tree.

| Evidence | What it demonstrates |
| --- | --- |
| [13 Display, English/light](evidence/tray-settings-end-to-end-2026-07-16/13-display-en-light.png) | Flat output/primary/mode controls |
| [14 Audio, Korean/light](evidence/tray-settings-end-to-end-2026-07-16/14-audio-ko-light.png) | Supported defaults and input/output volume layout |
| [15 Ethernet manual, English/dark](evidence/tray-settings-end-to-end-2026-07-16/15-network-en-dark.png) | Exact service picker and manual address/mask/router form |
| [16 Profile, Korean/minimum](evidence/tray-settings-end-to-end-2026-07-16/16-profile-ko-minimum.png) | 680×480 compact layout |
| [17 Audio, English/large text](evidence/tray-settings-end-to-end-2026-07-16/17-audio-en-large-text.png) | Simulated accessibility text size |
| [18 ColorSync, English/dark](evidence/tray-settings-end-to-end-2026-07-16/18-display-color-en-dark.png) | Per-display ICC profile controls without read-only color-space placeholders |
| [19 Unsupported audio, English/light](evidence/tray-settings-end-to-end-2026-07-16/19-audio-unsupported-en-light.png) | Default devices remain; unsupported volume controls are absent |
| [20 Ethernet DHCP, English/light](evidence/tray-settings-end-to-end-2026-07-16/20-ethernet-dhcp-en-light.png) | Ethernet DHCP form |
| [21 Wi‑Fi DHCP, Korean/light](evidence/tray-settings-end-to-end-2026-07-16/21-wifi-dhcp-ko-light.png) | Korean settings copy, Include, service, and DHCP labels |
| [22 Wi‑Fi manual, English/dark](evidence/tray-settings-end-to-end-2026-07-16/22-wifi-manual-en-dark.png) | Wi‑Fi manual form with synthetic documentation addresses |

The existing 12 Tray Surface v2 evidence pairs continue to cover empty, one, three, overflow, deletion, capture, result, Korean, dark, and large-text contained tray states. They remain detached evidence and do not prove the installed AppKit surface.

## Verification and remaining gaps

With every live and UI-audit environment flag unset, integrated `make verify` passed localization/source-policy lint; 366 default cases (134 XCTest and 232 Swift Testing cases, five opt-in skips); Swift Debug/Release; universal Xcode Debug/Release; Xcode Analyze; DMG/checksum creation; and mounted metadata, English/Korean resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID signature verification. `git diff --check` passed separately.

The verified no-Developer-ID DMG SHA-256 is `76bc6d9f1187ea30f68be16ee81ee4a334d877a4e26c2497f35a9ffc781678b3`. The artifact contains `arm64` and `x86_64`, English/Korean resources, an `/Applications` link, and an ad-hoc integrity signature only. It was not installed or launched.

Remaining manual evidence:

- 20 visible opens of the installed tray, actual anchor/material/dismissal, app/Space switching, red-close/frontmost behavior, and status-item state.
- Native English/Korean rendering, complete keyboard order, first responder, VoiceOver speech/rotor, real text size, contrast, and transparency.
- TCC and authorization UI, login approval/retry/reboot, quarantine/Gatekeeper, import/export, physical Intel, and live Keychain behavior.
- Explicitly approved hardware mutation and independent rollback for display topology/ColorSync, Core Audio defaults/volumes, and Ethernet/Wi‑Fi DHCP/manual IPv4.

No mock, detached screenshot, read-only discovery, build, package, or successful apply without a successful restore is hardware-mutation evidence.
