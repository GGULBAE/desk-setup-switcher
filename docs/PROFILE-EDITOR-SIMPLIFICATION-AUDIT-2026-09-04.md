# Profile editor simplification audit — 2026-09-04

## Outcome

The profile editor now follows the selected one-thing-at-a-time direction. At a normal 900×568 Settings size, a stable numbered rail keeps Display, Sound, and Network visible while only the selected step is editable. At 680×480 or an accessibility text size, the same information architecture becomes a segmented selector so the editor remains scrollable without compressing controls below useful widths.

The common path no longer starts with ColorSync or IP fields. Display leads with Extended/Mirror and the main display; Sound leads with output and volume; Network leads with one connection and an Automatic/Manual summary. Each card ends with one explicit inclusion switch. Resolution, refresh rate, ColorSync, audio input, mute, and service-specific IPv4 details remain available behind the selected step's **Advanced settings** disclosure.

## Strict review decisions

| Finding | Severity | Resolution |
| --- | --- | --- |
| The first implementation collapsed to a top segmented selector at 900×568, losing the selected concept's step rail | P1 | Reduced rail/content minimums so the numbered rail remains visible at the normal Settings width; only constrained/accessibility layouts collapse |
| The metadata GroupBox competed visually with the selected step | P2 | Replaced it with a flat heading, fields, and divider consistent with the selected direction |
| Last-application details consumed the primary editing viewport | P2 | Kept the information but collapsed it behind a localized disclosure by default |
| Selecting a Network connection disabled all other included services | P1 | Made selection transient and scoped the inclusion switch to the selected service; deterministic coverage proves other included services are preserved |
| Advanced validation targets could remain hidden | P1 | Field identifiers now select the owning step, expand Advanced when required, then transfer focus after layout settles |

## Evidence boundary

The selected reference and the 900×568 implementation were normalized into one side-by-side comparison before the final visual review. Focused implementation captures also covered Display, Korean Sound, Network, dark-mode Advanced Display/ColorSync and Network/manual IPv4, Korean 680×480 minimum size, large text, accessibility text, and validation. The full 18-fixture attached/offscreen Settings matrix passed. Focused profile policy and settings tests passed 47 cases.

All fixtures use synthetic adapter data and attached/offscreen AppKit/SwiftUI hosts. They do not invoke Capture, Apply Profile, TCC, login items, Keychain, display, ColorSync, audio, network, mouse, or keyboard mutation. Installed keyboard/focus/VoiceOver behavior and physical hardware mutation/rollback are not claimed. The repository-root `design-qa.md` was an unrelated pre-existing user file and was deliberately left untouched; the current comparison record stays in ignored build evidence instead of overwriting it.

The final canonical non-live `make verify` passed with 194 XCTest cases, 332 Swift Testing cases across 39 suites, one isolated native popover regression, the complete release-tooling policy/mock suite, Swift and universal Xcode Debug/Release builds, Analyze, packaging, checksum verification, and mounted universal-DMG metadata/resource verification. The current `git diff --check` also passes. The resulting unsigned development DMG SHA-256 is `81b16cdd9f2a0e56c8849fdc028fa2208b1dfac8a62e0c69ed59866be728b58d`; it was not uploaded or published. Behavior-focused commit `a9a5578` records the implementation and its bounded evidence.
