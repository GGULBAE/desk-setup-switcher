# Output mute — 2026-09-08

## Scope

The requested **소리 끔 / Output mute** option returns inside Profile → Sound → Output, after its device and volume. This controls the actual saved mute value, not participation in Apply. Input retains only device and volume. No per-setting inclusion switches, Advanced, Network, system-output, or other retired options return.

Core Audio snapshots read mute on the default output and provide a typed per-output capability catalog. A readable boolean is saved, including `false`; unsupported/unreadable values remain absent. The editor resolves the registered target device even when an old inclusion flag was off, and only offers a switch with readable/writable evidence. Without a saved value, the user can explicitly seed the current readable value; no opening/editing/saving action guesses one. Unsupported mute remains visible as a warning.

The normalizer now treats nonnil output mute like other registered values, including values retained in old profiles. JSON round trips preserve both boolean states without a schema bump. Absent mute stays absent and cannot silently unmute a device. Existing concrete-adapter validation, device-before-control planning, typed apply/read-back, and rollback are reused. Normal mode blocks an unavailable requested change; available-items mode can omit mute while applying supported changes. Neither launch nor opening Settings applies a profile.

## Verification

Focused domain/adapter/presentation/capability tests passed using synthetic UIDs and mock APIs. They cover both mute values, nil preservation, capture, target selection, normal/available-items behavior, registered mute versus dormant system output, operation/read-back/rollback, and the seven-kind vertical-slice registry.

The 19-fixture Settings offscreen matrix passed. The generated Korean full-height Output/Input layout, English dark layout, unsupported-control warning, Korean minimum size, and largest-text layout were visually inspected. At minimum height the form scrolls while the save bar remains fixed; the full-height fixture shows both cards with mute only in Output. Inclusion copy remains absent. Artifacts are reproducible with `DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 DESK_SETUP_REFINEMENT_EVIDENCE_DIR=<local-output-directory> swift test --filter TrayOffscreenEvidenceTests.rendersSimplifiedProfileSections` using the full Xcode toolchain. The local run wrote `.build/mute-ui-20260908`; generated host-only artifacts are not committed.

Full `make verify` passed: 554 app cases (198 parallel XCTest, 355 Swift Testing in 39 suites, and one isolated native-popover XCTest), release-tooling mocks, Swift Debug/Release, universal Xcode Debug/Release, Analyze, DMG/checksum, mounted resources/architectures, and release metadata. `git diff --check` passed. This gate used the existing worktree, preserving unrelated pre-existing Apply Preview changes; only the output-mute milestone is staged for its commit.

No live audio/display/network/input mutation, login registration, `sfltool`, Keychain operation, UI automation, or direct user-profile edit was performed. The user additionally authorized replacing the installed app after verification.

## Authorized local installation

The exact installed app completed a public normal-quit request, then was recoverably replaced from the verified read-only-mounted development DMG and relaunched. The installed executable matches the packaged executable, and its strict ad-hoc signature verification passed. This remains local `0.0.9`/build 1, not a signed/notarized public release.

- DMG SHA-256: `e3fecdd3565e483dcbf2aa1bf2bd5e55db22526099c95db39b988be6d7d70c02`.
- Packaged/installed executable SHA-256: `ce2eec5c46dcaf84aca33a572ef552e827a9e0f27404a5aa4fca7da42913f18b`.
- Previous app and both original profile documents are retained in the private, ignored `.build/installed-app-audio-mute-20260908.R56moK` recovery directory, with profile copies at mode `0600` and directory mode `0700`.
- The primary profile document retains all values and metadata. Startup normalization changes only saved output-mute inclusion flags from false to true; a canonical comparison ignoring inclusion flags is identical. The store persists the normalized document to both primary and regular backup; both pre-update documents remain preserved in the separate recovery directory. Byte identity with the pre-update primary/backup is **not** claimed.
- Existing consented auto-launch preferences remain enabled and unchanged. Registration, authorization prompts, logout/reboot, live Apply, and hardware rollback were not tested. Process/signature/hash checks establish installation/startup only, not an installed UI interaction claim.

## Next bounded check

Review the Output card's mute state and unsupported warning at normal and minimum window sizes without pressing Apply. Keep Input, tray actions, login preferences, and other settings unchanged; record only observed layout results and keep README verification status current.
