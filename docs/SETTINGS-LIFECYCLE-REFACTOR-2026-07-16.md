# Settings lifecycle and UI declutter refactor

## Goal

Remove routine or duplicated UI copy without hiding safety information, then re-audit the complete persisted-setting path from editor draft through storage, planning, execution, and read-back verification.

## What changed

- Removed the unused condition-editor implementation while retaining the Core condition schema, evaluator, import, persistence, and round-trip tests. Conditions remain dormant compatibility data and cannot trigger or invisibly block manual Apply.
- Removed duplicated Settings introduction text, nested picker labels, routine “saved” and login-registration success copy, low-risk visual tags, zero-valued result counters, and obsolete private helpers. Error, partial, unavailable, not-verified, rollback, permission, validation, progress, and accessibility information remains present.
- Made output counters data-driven so only zero values disappear. Every nonzero success, failure, skipped, unsupported, rollback, rollback-failed, and not-verified result remains visible and accessible.
- Rejected zero-operation preparation in both normal and available-items modes. A plan with no work can no longer execute and be reported as an application.
- Expanded the read-only Core Audio capability catalog to the actual input/output device targets. The editor now resolves volume capability and suggested value against the device the profile will apply to, not merely the current default device.
- Converted included-but-unavailable Audio, ColorSync, and service-IPv4 changes from silent drops into typed validation/plan omissions. Already-satisfied values remain true no-ops and do not become false omissions.
- Kept those previously included unavailable targets repairable in Settings with a text-and-symbol warning and Include-off control, including when a saved ICC disappears but other profiles remain; never-included unsupported controls remain absent.
- Changed private profile-file replacement to stage data and `0600` permissions before one same-directory atomic rename. A permission failure before commit leaves the previous destination intact.

## Lifecycle proof

The deterministic `SettingsLifecycleIntegrationTests` fixture exercises one value across all relevant layers without constructing a live macOS adapter:

1. seed and load a persisted profile;
2. edit output volume through `ProfileEditorModel`;
3. save through `ApplicationModel` and `ProfileStore`;
4. instantiate a fresh store and assert the exact included value and selected profile reload;
5. prepare and execute through an injected stateful adapter;
6. recapture and assert the executed operation is read-back `verified` with no remaining operation.

Adapter regressions separately cover unsupported/read-only targets, missing rollback evidence, no-op ordering, and normal-mode empty plans. Storage regression coverage proves a staged permission failure does not replace the existing file.

## Verification

The final integrated non-live `make verify` passed 401 default cases: 144 XCTest cases with five opt-in skips and 257 Swift Testing cases with two default-disabled opt-in cases. Localization/source policy, Swift Debug/Release, universal Xcode Debug/Release, Xcode Analyze, DMG/checksum creation, mounted English/Korean resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID classification all passed. `git diff --check` passed separately. The verified DMG SHA-256 is `f3aa610026179161208dec2cb2ef6185768843becd8e0e56bccc9f8abab37f2b`; it was not installed or launched.

## Evidence boundary

All automated evidence is deterministic and non-live. No display, audio, network, mouse, keyboard, TCC, Keychain, or third-party configuration mutation was run. Public custom `ProfileStore` file-name validation and explicit no-follow directory/file handling remain a separate storage-hardening task; the full native installed-app walkthrough and any hardware apply/rollback procedure also remain separately authorized work under the support matrix.
