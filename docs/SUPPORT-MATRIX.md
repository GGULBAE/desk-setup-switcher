# Support matrix

## Legend

- **Implemented:** source path exists, but no verification level is implied.
- **Mock verified:** deterministic injected/unit coverage passed; the real host was not changed.
- **Live-read verified:** an opt-in read-only test passed on the named hardware.
- **Hardware-mutation verified:** an explicit interactive apply and rollback procedure passed on physical hardware.
- **Experimental:** implementation uses a public preferences API with an undocumented key or lacks a stable supported OS contract.
- **Unsupported:** intentionally omitted; the app reports an item-level reason.
- **Pending:** implementation or required evidence is incomplete.

“Mock verified” and “live-read verified” must never be shortened to “hardware verified.” As of 2026-07-11, **no live setting mutation is hardware verified**.

## Platform

| Area | Target | Current evidence |
| --- | --- | --- |
| macOS | 14 Sonoma or later | Deployment target is 14.0; final 158-test local gate passes on macOS 26.5.2 with Xcode 26.6 |
| Apple Silicon | arm64 | Default tests and opt-in live-read smoke tests passed on an Apple M5 Mac |
| Intel Mac | x86_64 | Current Debug/Release and packaged executable contain x86_64; no physical Intel Mac run |
| Distribution | Direct no-Developer-ID DMG | Post-fix universal artifact, SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`, mount, metadata/resources, architectures, and ad-hoc app signature verified; not published and Gatekeeper path pending |
| CI | GitHub Actions | Initial run `29154880831` recorded the Swift 6.1 actor-isolation failure. Repair commit `4e45328` is pushed; [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed full `make verify` and unsigned-package upload on macOS 15/Xcode 16.4/Swift 6.1.2 |
| App Store | Not required | No sandbox/App Store claim |
| Signing/notarization | Optional | App is ad-hoc signed for integrity only; no Developer ID identity or notarization exists |

## App, profiles, and safety engine

| Area | Capability | Status and evidence |
| --- | --- | --- |
| App | Background/menu-bar-only lifecycle | Fresh final-DMG install launched from `/Applications` as background-only/menu-bar-only; popover rendered and `LSUIElement` is verified in the bundle |
| App | Login item | Default-on `SMAppService.mainApp` registration succeeded and BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it, re-enable restored enabled status, and final cleanup opted out with only disabled BTM history. Approval-required/retry and actual login-at-boot after a reboot remain pending |
| App | English/Korean UI | Fresh final-DMG popover and Settings rendered in Korean; a complete English/Korean walkthrough remains pending |
| App | Accessibility | An accessibility label passed inspection in the fresh install; full VoiceOver/keyboard/focus/contrast/text-size audit pending |
| Profiles | CRUD, ordering, selection, metadata, per-group/per-option inclusion | Mock verified at the storage/domain boundary; a fresh installed app created one schema-v1 Ready profile from a read-only snapshot with all four groups; remaining manual CRUD/UI flows pending |
| Profiles | Versioned JSON, schema 0→1 migration, semantic/resource limits | Mock verified |
| Profiles | Atomic primary/backup, corruption quarantine/recovery, local file permissions | Mock verified with temporary-file tests, including 0700 directories and 0600 managed files; sudden-power-loss durability is not claimed |
| Profiles | Import/export | Mock verified for size/schema/semantic validation, duplicate IDs, invalid selection, non-file input, source protection, and no-overwrite export |
| Snapshot | Detected/storable/unreadable/permission-required/unsupported item classification | Mock verified; concrete adapters live-read verified on one Apple Silicon Mac |
| Readiness | Ready/Partial/Unavailable and all/any/inverted conditions | Mock verified; combined read-only fact collection live-read verified |
| Apply | Normal/force preview, omissions, zero-operation rejection, no-op filtering | Mock verified; fresh snapshot profile produced a zero-operation plan with Apply and Force Apply disabled, with no mutation |
| Apply | Pre-execution stale-plan defense | Mock verified: conditions/profile/system are recaptured and execution-relevant operations/rollback payloads must match or the refreshed plan is shown again |
| Apply | One active transaction, deterministic order, fatal reverse rollback | Mock verified, including rollback failure separation |
| Apply | 15-second high-risk confirmation and protected rollback token | Mock verified with temporary apply, confirmation commit/failure, timeout, revert, and rollback; real display mutation not run |
| Diagnostics | Redaction and rotating local JSONL files | Mock verified for secrets, exact location, SSID, IP host portions, home paths, permissions, rotation, concurrency, and clearing |
| Diagnostics | Browse/refresh/clear in Settings | Implemented with sanitized events under Application Support; build verified, manual UI flow pending |

## System capabilities

| Group | Capability | API/mechanism | Status and evidence |
| --- | --- | --- | --- |
| Display | Active display discovery and stable identity | Public Core Graphics/ColorSync | Mock verified and live-read verified on the built-in display of one Apple M5 Mac |
| Display | Primary display and topology/origin | Core Graphics display configuration | Mock verified; live mutation not run |
| Display | Mirroring | Core Graphics display configuration | Mock verified; live mutation not run |
| Display | Logical/pixel mode and refresh rate | Core Graphics display modes | Mock verified; live mutation not run |
| Display | Temporary apply, confirmed commit, and rollback | Core Graphics app/session configure scopes | Mock verified: apply is app-only, **Keep Changes** re-commits session-only, and rollback is session-only; live mutation/timeout/app-exit behavior not run |
| Display | Rotation mutation | No safe public implementation | Unsupported; rotation is snapshot-only |
| Display | Activation/deactivation mutation | No safe public implementation | Unsupported; active state is snapshot-only |
| Audio | Device/UID/scope/default/control discovery | Public Core Audio | Mock verified and live-read verified on one Apple M5 Mac |
| Audio | Default input/output/system output | Public Core Audio properties | Mock verified; live mutation not run |
| Audio | Output scalar volume/mute | Capability/settable Core Audio properties | Mock verified; unsupported controls become item omissions; live mutation not run |
| Audio | Microphone capture | Not used | Unsupported and not requested |
| Network | Interfaces, link, IP/subnet, gateway, DNS, services, IPv4/proxy/order snapshot | CoreWLAN, SystemConfiguration, getifaddrs | Mock verified and live-read verified on one Apple M5 Mac; Ethernet-specific manual coverage pending |
| Network | Wi-Fi power | CoreWLAN | Mock verified; live mutation not run |
| Network | Saved-network association | CoreWLAN/macOS-held saved-network credential | Mock verified: target saved profile/access is preflighted and current association must have a safe rollback target; no password enters profiles/operations/logs; live mutation not run |
| Network | SSID read | CoreWLAN with authorization-aware result | Powered-on nil SSID is treated as ambiguous/unavailable, never proof of safe disassociation; mock verified and live adapter smoke passed, but denied/granted value matrix is pending |
| Network | DHCP/static IPv4, DNS, proxy, service-order mutation | No authorization/rollback-safe implementation | Unsupported; values may be snapshotted but mutation is omitted |
| Input | Pointer speed and natural scrolling snapshot/apply | CFPreferences, undocumented global keys | Experimental; mock verified, live-read verified, live mutation not run |
| Input | Key repeat, repeat delay, standard F-key snapshot/apply | CFPreferences, undocumented global keys | Experimental; mock verified, live-read verified, live mutation not run |
| Conditions | Display, audio input/output, USB/hardware, SSID, Ethernet, IP/CIDR | Core evaluator plus public read-only discovery | Mock verified; combined discovery live-read verified |
| Conditions | Authorized recent location | Core Location cached/one-shot request | Mock verified; no continuous tracking; denied/granted and stale-location manual matrix pending |
| Secrets | `SecretStore` generic-password implementation | Security framework, device-only after-first-unlock accessibility | Mock verified with synthetic bytes; live Keychain write deliberately not run |

## Explicitly unsupported features

- Automatic or background profile switching
- Logitech Options+, Razer Synapse, or other vendor profile control
- Vendor-specific DPI/button mapping or keyboard firmware settings
- Direct editing of Karabiner-Elements or any third-party app configuration
- UI scripting of System Settings or third-party apps
- Private macOS APIs, arbitrary shell execution, application telemetry, or cloud services
- Administrative network mutation without a public authorization and rollback design

## Read-only evidence recorded on 2026-07-11

The final local `make verify` gate passed with 158 tests: 83 XCTest and 75 Swift Testing cases. Six opt-in cases skip by default: five read-only hardware tests and one Keychain-write test. With `DESK_SETUP_LIVE_READ_TESTS=1`, the display, audio, network, input, and combined condition-context tests passed on an Apple M5 Mac running macOS 26.5.2. These tests call only capability/snapshot/read paths. No personal device identifier, SSID, IP address, or location is recorded in the repository.

## Local package evidence recorded on 2026-07-11

- Universal Debug/Release builds and the packaged executable contain `arm64 x86_64`.
- The post-fix no-Developer-ID DMG checksum is `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; mounted layout, bundle metadata, icon, English/Korean resources, and ad-hoc app signature passed the checked-in verifier.
- Downloaded CI artifact ID `8249295840` verified its checksum file and CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`; it differs from the local checksum because the DMGs are not byte-for-byte reproducible.
- The recorded local-DMG fresh copy to `/Applications` launched background-only/menu-bar-only; the popover and Settings rendered in Korean, and an accessibility label passed inspection.
- The fresh install created one schema-v1 Ready profile from a read-only snapshot with all four groups. Its zero-operation plan kept Apply and Force Apply disabled.
- Default-on `SMAppService` registration succeeded and BTM reported `[enabled, allowed, notified]`; UI opt-out disabled it, re-enable restored enabled status, and final cleanup opted out with only disabled BTM history.
- The local copy did not exercise quarantine/Gatekeeper, approval-required/retry states, or actual login-at-boot after a reboot. No full VoiceOver/keyboard, import/export, permission, or live-mutation procedure was run.

Coverage still absent:

- An external display, mirrored pair, display mode change, and unplug/replug identity matching
- An audio device without software volume/mute and a device hot-plug sequence
- Ethernet and both Wi-Fi permission-denied and permission-granted cases
- A physical Intel Mac
- Login-item approval-required/retry paths and actual login-at-boot after a reboot
- A downloaded/quarantined Gatekeeper install
- Any live setting apply or rollback
- A live Keychain round trip

## Manual hardware verification procedure

Every record must include date, macOS/app commit, broad hardware class with serials redacted, expected/actual result, rollback result, sanitized diagnostic event IDs, and tester. Never record a real SSID, exact location, IP host address, password, serial number, or raw exported profile.

### Shared preflight for every mutation

1. Obtain explicit approval for the named mutation and use a local build from a clean verified commit. Never run the procedure in CI.
2. Connect only the devices under test. Capture a read-only “Before” profile and independently record the original state in System Settings without sensitive values.
3. Confirm a manual recovery route: System Settings for audio/network/input; a second usable display or Screen Sharing for display tests; known saved Wi-Fi and Ethernet fallback for network tests.
4. Apply only one setting group and the smallest reversible change. Use the app's preview; cancel if the plan contains an unexpected group, missing rollback data, or an ambiguous identity.
5. Verify the changed setting through the relevant macOS UI and a fresh read-only snapshot. Use **Revert Now** when the display safety prompt offers it; otherwise apply the “Before” profile, then verify the original state independently.
6. Redact the resulting evidence and update this matrix. A successful apply without a successful restore is a failed verification.

### Display procedure

Use a built-in display plus one external display where available. First test an origin-only change, then primary/mirroring/mode separately. Keep an independent screen/control path available. Verify the initial change is temporary/app-only; let the 15-second timer expire once and confirm restoration, test **Revert Now**, then repeat and choose **Keep Changes** to exercise the session-only confirmation commit. Finally restore the “Before” profile. Also verify quitting during the temporary-confirmation window restores state. Do not test rotation or activation; they are unsupported.

### Audio procedure

Use a device identified by Core Audio UID. Change one default role, then volume and mute only if the adapter reports each control settable. Verify independently in Control Center/System Settings and restore. If a device has no software volume/mute, verify that the preview omits only that item without failing unrelated audio settings.

### Network procedure

Ensure an alternate connection exists and the target SSID is already saved by macOS. Test Wi-Fi power and saved-network association separately; never enter or export a password. Confirm the plan omits association when target saved access cannot be preflighted, the current association cannot be restored, or a powered-on interface has an unreadable/ambiguous SSID. Verify permission denial affects only SSID-dependent behavior, then grant permission through normal macOS UI and retest read-only discovery. Restore the original network before ending. Do not test static IPv4, DNS, proxy, or service-order mutation; they are unsupported.

### Input procedure

Because these operations use experimental global preference keys, record the original pointer/scroll/key values first and test one value at a time. Verify in System Settings or observable input behavior, restore immediately, and log the exact macOS version. A version-specific mismatch keeps the row experimental/unverified.

### Keychain and platform procedure

Run the gated synthetic Keychain round trip only after explicit approval, then confirm the test item was deleted. It is separate from setting mutation evidence. Repeat the safe build, default tests, app launch, and read-only discovery on physical Intel hardware before changing the Intel row from cross-build only.
