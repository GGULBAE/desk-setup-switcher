# Registered profile values — 2026-09-08

## Scope

- Remove “When applying · Included/Not included” and its toggle from main display, resolution, and both Sound sections. Keep the numbered Display/Sound navigation and Output/Input grouping.
- Every registered value in the six supported kinds participates across capture, editor/save, JSON import, storage, summary, and both preflight modes. Old supported exclusion flags no longer silently ignore visible values. Schema-v1 flags remain for compatibility and adapter contracts.
- Do not invent absent devices or volume values. Zero volume is a real registered value. An explicitly included but missing/invalid value retains validation; normalization does not repair untrusted data by guessing.
- Main-display selection requires exactly one saved primary. Ambiguous selection remains dormant until the user chooses; independent registered resolutions still participate. No default primary is guessed.
- Retired network, input, mirroring, origin, rotation, refresh-rate preference, mute, system-output, and color-profile behaviors remain excluded. Resolution still preserves the current refresh rate.
- Disconnected displays/devices stay visible when possible. Unavailable volume keeps a warning with device/review guidance, not a removed-toggle repair instruction. Runtime availability, read-only preview, explicit confirmation, stale-plan checks, and rollback remain unchanged.

## Verification

- Focused verification passed: 46 XCTest cases and 78 Swift Testing cases cover normalization/idempotence, import, snapshot, six-kind preflight payloads, missing/invalid values, editor registration, revert, save, and existing safety contracts.
- Full `make verify` passed: 195 parallel XCTest cases, 354 Swift Testing cases, the isolated native popover test, localization/lint, release-tooling mocks, Debug/Release builds, Analyze, universal packaging, and mounted metadata/resources.
- All 19 English/Korean Settings fixtures passed and produced paired PNG/evidence files in `.build/inclusion-ui-20260908/`. Visually inspected the Display, Sound, unsupported-volume, minimum-width, and full-height grouped-Sound renders. The existing 21-fixture tray matrix also passed.
- `git diff --check` passed. Existing unrelated Apply Preview/document edits were isolated from this milestone.

No live display/audio/network/input mutation, actual Apply, deletion, login registration, Keychain operation, or reboot is part of this work. Synthetic offscreen evidence is not installed interactive evidence.

## Local installation

The verified local `0.0.9`/build-1 package replaced the exact installed app after a normal quit and was relaunched from Applications. Mounted/installed executable SHA-256 matched:
`d7dbdab09f30244105b15af6a85b2c32f521beb46c872a6ff1eac9dad0f2fdd0`.
DMG SHA-256:
`1f6007f76b4de0ee0f188369e9f20e596b8fd5da3f66a8063e6317fcdc3472e4`.

Both primary and backup profile files remained byte-identical after launch. The three existing profiles had no excluded registered supported values, so this install required no inclusion migration. The saved consented launch-at-login preference stayed ON; effective OS registration and reboot were not retested. No `sfltool` command ran.

The previous app and private 0600 profile copies remain recoverable in `.build/installed-app-audio-inclusion-20260908.EyxU5g/`, with local restoration instructions. This is a local development build, not a public release or hardware-apply verification.

## Next bounded check

After the verified build is available, inspect only the installed Display and Sound layouts: titles, device/resolution pickers, volume controls, Output/Input grouping, and absence of inclusion copy/switches. Do not Apply, change permissions, or delete profiles. Record any layout discrepancy and keep README status current; this does not open a hardware-test or wider redesign task.
