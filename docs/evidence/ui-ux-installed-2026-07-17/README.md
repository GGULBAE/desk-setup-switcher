# Installed UI/UX evidence — 2026-07-17

This directory contains visual evidence from the final installed package and synthetic large-text/error fixtures. It contains no SSID, serial number, credential, geographic location, diagnostics payload, or live workflow review values.

## Installed geometry

| Check | Observation |
| --- | --- |
| Tray first open | Outer `x=1163 y=31 w=394 h=342`, center `(1360, 202)`; SwiftUI host `x=1176 y=44 w=368 h=316`, center `(1360, 202)`; delta `(0, 0)` pt |
| Tray repeated open | 20/20 samples retained the same outer and hosted frames and a `(0, 0)` pt center delta |
| Settings initial/reopen | `900×568`; 10/10 normal-paced close/reopen samples retained the frame |
| Settings minimum | A `500×300` request was clamped immediately to `680×480`; Profile → System retained the minimum |
| Workflow initial | Native `620×532`, corresponding to `620×500` content |
| Workflow minimum | A `500×300` request was clamped immediately to native `520×392`; Escape closed without Apply |

“First open” means the first measured tray open after reinstall with the existing profile store and UserDefaults retained; it was not a clean first-ever launch or empty-store test. Sequence counts are operator-observed. The committed images show endpoints and final states rather than every sample or input event.

The first/repeated tray images are [popover-first.png](installed/popover-first.png) and [popover-open-20.png](installed/popover-open-20.png). Settings evidence is [settings-minimum.png](installed/settings-minimum.png) and [settings-system-enabled.png](installed/settings-system-enabled.png). Installed workflow screenshots were inspected locally but omitted from the repository because they display live review values; the geometry table records the bounded observation and the synthetic workflow image below records minimum-size containment without host data.

## Synthetic containment and state evidence

- [Korean empty tray with simulated accessibility text](synthetic/empty-ko-accessibility.png)
- [English capture failure in light appearance](synthetic/capture-failure-en-light.png)
- [Korean permission workflow at minimum size with simulated accessibility text](synthetic/permission-ko-minimum-large-text.jpg)

## Package and safety record

- DMG SHA-256: `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`
- Installed executable SHA-256: `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305`
- Package architectures: `x86_64 arm64`
- Profile store and backup: byte-for-byte unchanged from the preflight copies
- Login defaults: unchanged from preflight
- Login registration-attempt count: unchanged from its pre-existing value

No Apply, Capture, TCC, login-item, display, ColorSync, audio, network, mouse, or keyboard-setting mutation was performed. The System status refresh was read-only. The screenshots prove installed rendering and geometry only; they do not claim a full VoiceOver walkthrough or hardware behavior.
