# Completion criteria and evidence ledger

This ledger prevents planned work from being reported as complete. A box may be checked only after the named evidence is committed. Hardware-dependent rows may use implementation + mock evidence + capability checks + an explicit manual procedure, but must remain labelled “not hardware-verified” until tested on suitable equipment.

## Baseline evidence (2026-07-11)

- [x] MIT license exists.
- [x] Full Xcode 26.6 and Swift 6.3.3 are available locally through a process-level `DEVELOPER_DIR` override.
- [x] Required Apple framework imports type-check for arm64 and x86_64 with a macOS 14 target.
- [ ] Any application feature is implemented.
- [ ] Any build, test, app launch, package, or CI run succeeds.

## Product and app lifecycle

- [ ] Xcode opens the checked-in project and lists shared schemes. Evidence: command and scheme output.
- [ ] Debug build succeeds for macOS 14+. Evidence: clean build log.
- [ ] Release build succeeds for both supported architectures. Evidence: archive/build inspection.
- [ ] Packaged app launches. Evidence: launch smoke-test procedure and result.
- [ ] App remains in the menu bar and has no default Dock icon. Evidence: Info.plist plus manual observation.
- [ ] `SMAppService` login registration, status, failure, and opt-out flows work. Evidence: unit/UI state tests plus manual result.
- [ ] English and Korean UI resources load. Evidence: localization test/manual screenshots.
- [ ] VoiceOver labels and keyboard navigation are audited. Evidence: checklist and manual result.

## Profiles and storage

- [ ] Create, read, edit, duplicate, delete, reorder, enable, and update-from-snapshot work.
- [ ] Name, description, SF Symbol, group inclusion, and per-option inclusion persist.
- [ ] Versioned serialization and migrations pass fixtures.
- [ ] Atomic save, backup, corruption quarantine, and recovery pass fault-injection tests.
- [ ] Import/export validation, size limits, duplicate IDs, malicious JSON, and future schema handling pass tests.
- [ ] Last apply result and timestamp persist without leaking sensitive values.

## Snapshot and adapters

- [ ] Snapshot distinguishes detected, storable, unreadable, permission-required, and unsupported values.
- [ ] Display adapter has stable matching, snapshot, validation, apply plan, backup, rollback, and safe-confirmation design.
- [ ] Audio adapter uses UIDs and handles default input/output/system output, volume, mute, and unsupported controls.
- [ ] Network adapter covers required discovery/conditions and safely handles Wi-Fi credentials and permission denial.
- [ ] Mouse/keyboard adapter covers the supported common settings and labels non-public preference keys experimental.
- [ ] No vendor configuration, UI automation, foreign-file mutation, or arbitrary shell execution is used.

## Conditions and apply engine

- [ ] All/any/inverted display, audio, USB/hardware, SSID, Ethernet, IP/CIDR, and authorized-location conditions are tested.
- [ ] Ready, Partial, and Unavailable are derived from item capabilities and conditions and shown without color-only meaning.
- [ ] Normal apply rejects incomplete profiles.
- [ ] Force apply previews and records successes, failures, and skips, and rejects a zero-operation plan.
- [ ] No-op settings are skipped.
- [ ] Fatal failure rolls completed operations back in reverse order.
- [ ] Rollback failure remains distinguishable from the initiating error.
- [ ] Display-risk confirmation can restore the backed-up state after a timeout.

## Security and privacy

- [ ] All data and diagnostics remain under Application Support except user-selected import/export destinations.
- [ ] Credentials use Keychain and never enter JSON, backups, or logs.
- [ ] Redaction tests cover passwords, exact location, sensitive network data, and home paths.
- [ ] Permissions are minimal, explained before prompting, and denial degrades only dependent features.
- [ ] Import paths and JSON cannot cause traversal, resource exhaustion, or unexpected network/file access.
- [ ] Source audit confirms no telemetry or app-owned outbound requests.

## Quality, packaging, and delivery

- [ ] Required repository/community/privacy/architecture/support documentation is complete and accurate.
- [ ] Unit and mock integration suites pass.
- [ ] Static lint and Xcode analyze pass.
- [ ] GitHub Actions passes on the pushed milestone.
- [ ] Versioned unsigned DMG contains the app and Applications link.
- [ ] SHA-256 checksum is generated and verifies.
- [ ] New-Mac install, Gatekeeper, optional signing, and notarization instructions are tested/reviewed.
- [ ] Working tree is clean after the final release commit.
- [ ] All completed milestones are pushed and no mandatory item remains.

## Manual hardware evidence format

Record date, macOS version, hardware/device identifiers with serials redacted, exact procedure, expected result, actual result, rollback result, log event IDs, and tester. A mock test is not a substitute for this record; the support matrix must distinguish the two.
