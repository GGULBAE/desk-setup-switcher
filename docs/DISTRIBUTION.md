# Distribution

## Current status

The version 0.1.0 no-Developer-ID packaging path passes locally. The final 2026-07-17 integrated gate covered 446 checks: 144 XCTest cases, 301 Swift Testing cases across 38 suites, and one separately executed native `NSPopover` regression. Universal Debug/Release, Analyze, DMG creation, SHA-256 validation, mounted metadata/resources, `arm64 x86_64`, and ad-hoc/no-Developer-ID signature classification passed. Current DMG SHA-256 is `82b05e6a3b1b20978c85c4d82d0976237a731c76c07bcd7d1729a84e3e0b6f21`. The package was reinstalled to `/Applications`, where the executable SHA-256 is `40876bd671dd4286fa4684192097f6dbd702df899bccf8efb588b244c3d27305`. The [current installed audit](UI-UX-SIMPLIFICATION-INSTALLED-AUDIT-2026-07-17.md) and [evidence index](evidence/ui-ux-installed-2026-07-17/README.md) are the authoritative UI/package record for this build.

Initial Actions run `29154880831` for implementation commit `0d8f510` exposed the Swift 6.1 actor-isolation issue. Repair commit `4e45328` is pushed, and [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) succeeded on 2026-07-11 under macOS 15/Xcode 16.4/Swift 6.1.2; full `make verify` and unsigned-package upload passed. No release has been published, and the downloaded/quarantined Gatekeeper path remains untested.

Developer ID signing and notarization remain optional and unimplemented because the repository has no Apple signing identity or notarization credentials.

## Baseline no-Developer-ID release

Run:

```sh
make package
make verify-package
```

`make package` performs the universal Release Xcode build with automatic signing disabled, copies the app into a temporary staging directory, then applies a free ad-hoc signature:

```text
Signature=adhoc
Authority=(none)
```

That signature supplies a local code-integrity envelope and satisfies the packaging design's code-signature prerequisite. It does **not** authenticate GGULBAE, establish an Apple trust chain, provide a Developer ID identity, notarize the app, or bypass Gatekeeper. The DMG itself is not Developer ID signed or notarized. The artifact keeps `unsigned` in its name to mean “not identity-signed,” even though the contained app is ad-hoc signed.

The command creates:

- `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`
- `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg.sha256`

The historical 2026-07-11 post-fix locally verified DMG has SHA-256 `246af7c21ac9f1ffd4c6f7523f857737f148e4354a948b0e4d9a2123bb5d827f`; the current checksum is recorded above.

Downloaded CI artifact ID `8249295840` verified its checksum file and CI-generated DMG SHA-256 `d3894d8e7efdd775c5983c63051ec4181d33e039a40b83163a39a24c898be6b5`. The local and CI-generated DMGs are not byte-for-byte reproducible, so both checksums remain part of the evidence.

The DMG contains `Desk Setup Switcher.app` and an `/Applications` symbolic link. `make verify-package`:

- parses and recomputes the single SHA-256 entry;
- mounts the image read-only;
- validates the executable and `/Applications` link;
- confirms `arm64 x86_64`;
- checks bundle identity, versions, deployment target, `LSUIElement`, location usage copy, icon, and English/Korean resources;
- rejects any identity-signed app in an artifact named unsigned;
- requires and structurally verifies the ad-hoc app signature.

The checksum detects accidental or malicious byte changes only when the checksum itself comes from a separately trusted source. Neither the checksum nor `codesign --verify` supplies publisher identity.

`make verify` is the full release-candidate gate and also runs lint, default tests, Debug/Release Swift and Xcode builds, and Xcode Analyze. CI is configured to use the same command and does not opt into live discovery, Keychain writes, or setting mutations.

## Manual evidence and remaining gaps

A separately authorized 2026-07-17 follow-up reinstalled the current package to `/Applications` and exercised only bounded UI geometry. Twenty measured popover opens had exact center delta `0`. A `500×300` Settings request clamped to `680×480`, while the normal `900×568` frame remained stable across ten opens. A `500×300` workflow request clamped to `520×392`; its initial frame was `620×532` with `620×500` content, and Escape closed it. Apply, Capture, TCC, login, and system-setting mutations were not invoked.

A historical 2026-07-11 DMG was also installed fresh to `/Applications` and launched background-only/menu-bar-only. Its then-current popover and Settings window rendered in Korean, and an accessibility label passed inspection. It created one schema-v1 Ready profile from a read-only snapshot with all four setting groups; its zero-operation plan kept Apply and Force Apply disabled. That historical evidence does not replace current VoiceOver or focused-control AX verification.

Default-on `SMAppService` registration succeeded and Background Task Management reported `[enabled, allowed, notified]`. UI opt-out moved it to disabled, and re-enable restored enabled status. Final cleanup opted out and left only disabled BTM history.

This does not complete the release matrix:

- Login-item approval-required and failure/retry paths were not exercised, and actual login-at-boot after a reboot was not tested.
- No full VoiceOver/keyboard audit, focused-control AX observation, import/export workflow, or permission-denial matrix was run. The recorded Escape close is not a complete keyboard walkthrough.
- A locally built file does not exercise download quarantine. Gatekeeper/Open Anyway remains untested on a clean user account or Mac.
- The x86_64 slice was inspected, but the app was not executed on physical Intel hardware.
- No display, audio, network, mouse, or keyboard mutation was run.

## Installing an unsigned build

An app without a Developer ID identity can be blocked after download. Verify the published SHA-256 checksum first:

```sh
shasum -a 256 -c Desk-Setup-Switcher-0.1.0-unsigned.dmg.sha256
```

Then mount the DMG, drag the app to Applications, and use a normal macOS approval flow:

1. Attempt to open the app once.
2. Open **System Settings → Privacy & Security**.
3. Confirm **Open Anyway** for Desk Setup Switcher and approve the warning.

On macOS versions that offer it, Control-clicking the app in Finder and choosing **Open** can provide an equivalent explicit approval. Never disable Gatekeeper globally, remove quarantine recursively, or tell users the ad-hoc build is Developer ID signed or notarized.

This exact quarantined install flow has not yet been recorded, so these steps remain guidance rather than verified release evidence.

## GitHub Actions release path

The CI workflow runs `make verify` for pushes to `master`, pull requests, and manual dispatch, then uploads the no-Developer-ID DMG/checksum. The release workflow triggers on `v*` tags, rejects a tag that does not equal `v` plus `CFBundleShortVersionString`, reruns `make verify`, and uses GitHub's token to create an explicitly unsigned release.

Run `29154880831` preserves the initial compiler-compatibility failure history. Repair [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed full `make verify` and unsigned artifact upload for `4e45328`, including the SHA-pinned `actions/checkout` v7.0.0 and `actions/upload-artifact` v7.0.1 Node-24 majors. The release workflow has not run. A tag must not be pushed until the remaining release/manual matrix has been accepted and the completion ledger is current.

## Optional Developer ID signing

Signing requires an Apple Developer Program membership, a Developer ID Application certificate, protected credentials, hardened-runtime decisions, and any required entitlements. None are checked in. A future release operator must add a reviewed, reproducible path that:

1. Builds the universal Release app with hardened runtime and reviewed entitlements.
2. Signs every required nested code object and the app with the Developer ID Application identity.
3. Verifies with `codesign --verify --deep --strict --verbose=2` and inspects the designated requirement and authority chain.
4. Builds and signs the DMG, then records identity/team metadata without exposing credentials.

Until a real run passes, release notes and artifact names must say **unsigned** or **no Developer ID**. An ad-hoc signature is not Developer ID evidence.

## Optional notarization and stapling

After a valid Developer ID signing path exists, submit the DMG with `xcrun notarytool submit --wait` using a protected Keychain profile or CI secret. A successful submission is insufficient by itself: staple the ticket, validate the staple, and assess the app/DMG with `spctl` on a clean system.

Credentials, certificate exports, API keys, and notarization profiles must never be committed or printed. Fork pull requests must not receive release secrets. Notarization is currently **not implemented and not tested**.

## Release evidence checklist

For each release, record:

- tag and commit;
- Xcode, Swift, SDK, and macOS versions;
- lint, test, Debug/Release build, Analyze, and `make verify` results;
- executable architecture and signature-class inspection;
- DMG file listing, mounted-image validation, and checksum verification;
- packaged-app launch, menu-bar/Dock, login-item, import/export, diagnostics, and accessibility results;
- quarantined Gatekeeper procedure on a clean user or Mac;
- signing, notarization, and stapling status, explicitly “not performed” when absent;
- read-only and hardware-mutation status from the support matrix;
- CI run and release URL.

Do not include personal device identifiers, real SSIDs, exact locations, IP host addresses, credentials, or unredacted diagnostics in release evidence.
