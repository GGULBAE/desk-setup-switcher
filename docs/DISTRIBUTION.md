# Distribution

## Current status

No installable artifact has been produced yet. This document defines the release path that must be verified before the first release.

## Baseline unsigned release

The required free release path builds a universal macOS application without a Developer ID identity, verifies its bundle metadata and architectures, and creates a versioned DMG containing:

- `Desk Setup Switcher.app`
- an `Applications` folder alias
- a separately published SHA-256 checksum

The packaging command must start from a clean Release build, use only tools included with macOS/Xcode, and fail when the bundle, architecture, DMG contents, or checksum is wrong. It must not ad-hoc-sign and then describe the result as Developer ID signed.

## Installing an unsigned build

Unsigned apps downloaded from the internet can be blocked by Gatekeeper. A user should first verify the published SHA-256 checksum, drag the app to Applications, then use one of Apple's normal approval flows:

1. Attempt to open the app once.
2. Open **System Settings → Privacy & Security**.
3. Confirm **Open Anyway** for Desk Setup Switcher, then approve the warning.

On macOS versions that expose it, Control-clicking the app in Finder and choosing **Open** can provide the equivalent explicit approval. Users should not disable Gatekeeper globally and documentation must never recommend `spctl --master-disable` or removing quarantine recursively.

## Optional Developer ID signing

Signing requires an Apple Developer Program membership, a Developer ID Application certificate, and protected CI secrets or a local keychain identity. A release operator will:

1. Archive the universal Release build with hardened runtime enabled.
2. Sign nested code and the app using the Developer ID Application identity and production entitlements.
3. Verify with `codesign --verify --deep --strict --verbose=2` and inspect designated requirements.
4. Build the DMG and sign the DMG.

Exact checked-in commands and entitlements will be added and tested with the packaging milestone. The unsigned path remains supported.

## Optional notarization and stapling

After signing, submit the DMG with `xcrun notarytool submit --wait` using a Keychain profile or protected CI credentials. Accepting a notarization request is not enough: staple the ticket with `xcrun stapler staple`, validate it, and assess the app with `spctl` on a clean system.

Credentials, certificate exports, API keys, and notarization profiles must never be committed or printed in logs. Fork pull requests do not receive release secrets.

## Release evidence

For each release record the tag/commit, Xcode and SDK versions, Debug/Release/test/analyze results, universal architecture inspection, DMG file listing, checksum verification, signing/notarization status, Gatekeeper install test, and hardware verification status. “Unsigned” must remain explicit in artifact names and release notes when applicable.
