# Installed empty-state and apply-handoff follow-up — 2026-07-16

> Historical installed follow-up. The later [UI stability audit](UI-STABILITY-AUDIT-2026-07-16.md) incorporates the subsequent tray, Settings, and refreshed-preview screenshots and supersedes the current implementation notes here.

## Scope and safety boundary

Two user-provided screenshots from the preceding installed build showed an empty tray whose inner content was horizontally displaced and an apply preview that appeared to have no effect. The screenshots were inspected only for layout and workflow semantics; they are not copied into the repository. Diagnostics were inspected only through sanitized component/code metadata. No display, ColorSync, audio, network, mouse, keyboard, TCC, Keychain, or profile-store mutation was performed by development or verification commands.

One explicitly gated live-read check prepared the selected profile twice through the current adapters. The first failing assertion showed that rendering whole `ApplyPreparation` operands could expose local values in transient test output, so the regression now asserts a standalone Boolean and provides only sanitized mode/group/count/equality flags. The final normal and available-items run passed without applying any operation. This is adjacent read-only evidence, not hardware-mutation proof.

## Empty-state diagnosis and correction

The native popover body was present at the expected size, but its attached hosting view exposed a left-heavy horizontal safe area. The SwiftUI root inherited that value and then added its own symmetric padding, so the inner header and empty state were shifted even though pure geometry tests reported symmetric insets. The tall native unavailable-content container also imposed unnecessary empty-state height and centering behavior.

The root now ignores container horizontal safe-area values and owns the only 16-point horizontal inset. The empty state is an explicit compact stack with a decorative symbol, localized headline, wrapping caption, and combined accessibility element. Vertical scroll content margins are zeroed without changing the fixed open-session viewport.

`TrayOffscreenEvidenceTests` injects a 24-point left and zero-point right `NSHostingView.safeAreaInsets`. With the correction, the measured empty-state ink center is 3.5 pixels from the viewport center, within the four-pixel raster tolerance. Temporarily removing the correction moves it 8.5 pixels off center and fails the regression. This proves the source-level safe-area ownership contract; only a user-driven launch can confirm the final native appearance on the installed OS.

## Review and apply diagnosis and correction

The tray row previously said Apply even though that action only opened a persistent review window. The actual mutation boundary was the separate Apply Profile button, so the first label overstated what had happened. Several confirmation guards also returned without presenting a reason, and a changed execution preflight returned to preview without clearly saying that nothing had been applied.

The row now says Review or Review Available. The preview explicitly says that no setting changes until Apply Profile is pressed. A stable reviewed plan is recaptured, proven execution-equivalent, and reaches the injected adapter exactly once. If the stored profile, operations, omissions, payload, or rollback evidence changes, no adapter is called; the preview is replaced with an orange refreshed-state notice and requires another Apply Profile confirmation. Synthetic-mode, missing-preview, and transaction-lock rejection reasons are visible in the workflow. The true confirmation includes an accessibility hint that it executes reviewed operations and shows itemized results.

Deterministic tests cover both branches:

- stable review → execution preflight → exactly one adapter apply call → itemized result;
- changed execution preflight → zero adapter calls → visible refreshed review.

## Repeated refreshed-review diagnosis and correction

A later installed screenshot showed the orange refreshed-review notice recurring after every Apply Profile confirmation. The gated read-only reproduction proved that the visible operation values, capabilities, readiness, and counts were stable, but one Core Audio operation and rollback payload differed at the raw byte level. `JSONEncoder` may emit keyed enum fields in different object order, so byte equality incorrectly classified semantically identical commands as changed Mac state.

Core Audio now emits sorted-key JSON. The core comparison also canonicalizes any JSON object before comparing operation and rollback payloads, then falls back to exact bytes for non-JSON data. A deterministic regression proves reordered keys are equivalent while a changed rollback value remains non-equivalent. This preserves stale-state protection without allowing encoder order to create an infinite review loop.

After the correction, the selected profile's adjacent preparations passed in both normal and available-items modes in 0.148 seconds. No apply, authorization prompt, or setting mutation ran.

## Verification, package, and installation

With all live and UI-audit flags unset, `make verify` passed with zero failures:

- 134 XCTest cases, including five skipped opt-in cases;
- 237 Swift Testing cases, including two disabled opt-in cases;
- English/Korean localization and source-policy lint;
- Swift Debug/Release and universal Xcode Debug/Release;
- Xcode Analyze;
- DMG creation, checksum, read-only mount, metadata/resources, `x86_64 arm64`, and ad-hoc/no-Developer-ID signature verification.

The verified DMG SHA-256 is `62a2999a6d235f163753e7cccccf34b3b64605405635ca562a621c2e4bb48662`. It replaced `/Applications/Desk Setup Switcher.app` through a staged copy with rollback backup. The installed bundle ID, version 0.1.0, architectures, and code signature passed read-only checks. The app was not launched automatically after replacement. The pre-canonicalization package SHA-256 `e2927513543903b794bea08628064b29c12604e18706bef169c20b3e89760bcd` is historical.

## Remaining manual evidence

- Launch the reinstalled app and confirm the empty tray's header, divider, icon, headline, and caption are visually centered over repeated opens.
- Confirm a profile row says Review, the workflow notice says no change has occurred, and Apply Profile produces a visible progress/result or a specific rejection/refreshed-review message.
- Treat any real Display, ColorSync, Audio, Ethernet, or Wi-Fi change as a separate hardware-mutation procedure with preflight snapshot, visible 15-second Keep/Revert path where applicable, and independently verified rollback.

No installation checksum, detached render, read-only preparation, or mock adapter success is hardware-mutation evidence.
