# Tray activation and first-click focus — 2026-09-11

## Problem

The production app is an `LSUIElement` accessory app. Clicking its status item can deliver the action while another application is still active. The previous open path presented the `NSPopover` but did not explicitly request application activation or make the attached content window key, so the first visible frame could retain inactive control colors and muted button emphasis.

## Change

For every accepted tray-open generation, the controller now performs this ordered sequence:

1. Request application activation through the tray surface factory.
2. Present the existing app-owned `.applicationDefined` popover from the status-item anchor.
3. Ask the popover's attached content window to become key.
4. If AppKit reports activation later, repeat the key request only while that same open generation is current.

The pending activation observation is removed when activation arrives or the tray closes. Each observation has a request-scoped generation token, so a queued callback from a closed generation cannot remove or complete a newly opened generation's observer. The production factory uses the current `NSApplication.activate()` API, and the popover surface uses `NSWindow.makeKey()`. The app remains an accessory app: it does not adopt the regular activation policy, create a Dock icon, reorder private popover chrome, fake SwiftUI active state, or change popover dismissal behavior.

Activation and key-window requests are injected surface operations. Unit and native-offscreen test doubles deliberately keep them inert, so ordinary tests cannot steal keyboard focus or mutate the user's live application state.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter TrayPopoverControllerTests -Xswiftc -warnings-as-errors` passed the focused tray-controller suite.
- The regressions verify the initial `activate → show → make key` event order, one activation/key request for an accepted open, no duplicate request while the same generation is already open, a fresh sequence after close and reopen, a second key request after delayed activation, cancellation when the tray closes first, and rejection of an old queued activation callback without invalidating the reopened observation.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make verify` passed the full non-live repository gate: lint and localization policy, Swift tests, Debug/Release builds, universal Xcode builds, Analyze, package/checksum, mounted-resource and architecture checks, and signature classification.
- No app was installed or launched, and no live display, audio, network, mouse, keyboard, login-item, or other system-setting mutation was performed for this follow-up.

## Remaining installed check

This source and deterministic evidence does not prove the final macOS compositor/focus timing. A user-authorized installed check should leave another app in front, click the menu-bar item once, and confirm that the popover immediately uses active control colors, reports its content window as key, accepts keyboard navigation and Escape, and dismisses normally. The check should also record which application owns foreground focus after dismissal before any focus-restoration policy is chosen. Until that evidence is recorded, installed first-click appearance, focus, and post-dismissal foreground behavior remain pending rather than claimed.
