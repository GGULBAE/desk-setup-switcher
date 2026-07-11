# Support matrix

## Legend

- **Planned:** specified but not yet implemented.
- **Mock verified:** implemented and covered by synthetic tests, not confirmed on physical hardware.
- **Hardware verified:** tested using the documented manual procedure.
- **Experimental:** uses a safe public mechanism with an undocumented preference key or otherwise lacks a stable supported OS contract.
- **Unsupported:** intentionally not implemented.

At the current pre-alpha baseline every product capability is **Planned**. Nothing is hardware verified.

## Platform

| Area | Target | Current evidence |
| --- | --- | --- |
| macOS | 14 Sonoma or later | Required framework imports type-check against macOS 14 |
| Apple Silicon | arm64 | Framework import type-check only |
| Intel Mac | x86_64 | Cross-target framework import type-check only |
| App Store | Not required | Unsigned/direct distribution planned |

## Capability plan

| Group | Capability | Intended API | Status |
| --- | --- | --- | --- |
| App | Menu-bar-only lifecycle | SwiftUI `MenuBarExtra`, `LSUIElement` | Planned |
| App | Login item | `SMAppService.mainApp` | Planned |
| Display | Discovery/identity | Core Graphics | Planned |
| Display | Primary/topology/mirroring/mode | Core Graphics display configuration | Planned |
| Display | Refresh rate | Core Graphics display modes | Planned |
| Display | Rotation/activation | Public API only where available | Planned; unsupported otherwise |
| Display | Timed restore | App transaction + Core Graphics backup | Planned |
| Audio | Device discovery/defaults | Core Audio | Planned |
| Audio | Output volume/mute | Core Audio capability properties | Planned |
| Network | Wi-Fi state/SSID | CoreWLAN with permission-aware behavior | Planned |
| Network | Ethernet/interfaces/IP/subnet | Network/SystemConfiguration/getifaddrs | Planned |
| Network | Gateway/DNS snapshot | SystemConfiguration dynamic store | Planned |
| Network | Wi-Fi power/saved association | CoreWLAN | Planned |
| Network | DHCP/static IP/DNS/proxy/order mutation | Public API + authorization if safely reversible | Planned evaluation; not core |
| Input | Pointer speed/scroll direction | CFPreferences with reviewed keys | Planned experimental |
| Input | Repeat/delay/function-key preference | CFPreferences with reviewed keys | Planned experimental |
| Conditions | Device/network/IP/CIDR | Core domain + adapter snapshots | Planned |
| Conditions | Location | Core Location, only when selected/authorized | Planned |

## Explicitly unsupported core features

- Logitech Options+ profiles
- Razer Synapse settings
- Vendor-specific DPI or button mapping
- Keyboard firmware settings
- Direct editing of Karabiner-Elements rules
- UI scripting of System Settings or third-party apps
- Private macOS APIs
- Automatic profile switching

## Capability policy

A setting is enabled only after the live adapter reports it can read and/or write the exact property on the matched device. Missing software volume/mute, denied location, ambiguous device identity, unsupported modes, and administrative requirements are item-level capability results. They do not imply application failure.

## Hardware verification

Manual procedures will cover at least one built-in and one external display, an audio device without software controls when available, Wi-Fi permission denied/granted cases, Ethernet, and both supported CPU architectures where hardware is available. Results are appended to the release checklist; absence of hardware remains explicit.
