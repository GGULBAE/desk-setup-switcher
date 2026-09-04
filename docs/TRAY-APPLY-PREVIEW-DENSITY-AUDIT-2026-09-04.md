# Tray and Apply Preview density audit — 2026-09-04

## Scope and evidence boundary

This pass addresses three user-reported presentation problems:

1. a three-profile menu-bar popover retained a large empty tail;
2. Apply Preview's warnings and repeated section copy obscured the actual changes;
3. omissions and validation messages were difficult to scan and included an English ColorSync sentence in the Korean UI.

The supplied references were inspected as raster evidence before implementation. The second and third supplied files were byte-identical, so they represent one Apply Preview state rather than two independent states. All implementation evidence is synthetic and offscreen. No Capture, Apply, permission, login-item, Keychain, display, ColorSync, audio, network, mouse, or keyboard mutation was invoked.

The root `design-qa.md` was already an unrelated untracked user file. It was neither opened nor modified. Product-design iteration notes are therefore written to the ignored build directory, while this tracked audit records only the repository milestone.

## Measured references

| Surface | Supplied reference | Normalized review state |
| --- | --- | --- |
| Tray | 492×655 screenshot; app surface cropped to 368×560 | Korean, dark appearance, three profile cards, no transient result banner |
| Apply Preview | 714×634 screenshot; app content cropped to 620×500 | Korean, dark appearance, two audio changes, two omissions, two validation messages |

The first tray card ended near the top as expected, but the third card ended roughly 110 points before the 560-point viewport bottom. Apply Preview devoted more vertical and visual weight to a three-line Safety summary and four individually listed diagnostic messages than to the two intended changes.

## Selected direction

The selected direction keeps the existing safety and transaction model while changing information hierarchy:

- size exactly three standard tray cards at 480 points; four or more profiles retain the 560-point overflow viewport;
- show change, skip, and review counts immediately after the heading;
- render each planned operation as one compact card with a direct current → target value;
- group omissions, validation issues, and rejections in one **Review details** disclosure;
- expand those details automatically when the plan cannot execute;
- keep the Beta hardware-verification status, refreshed-plan warning, protected-change timer, final read-only notice, Escape cancel behavior, and non-default Apply action explicit;
- start Apply Preview at 620×440 and pin short-state actions to the bottom without creating a second scroll region.

## Iteration log

### Iteration 1

- **P1:** Three profiles inherited the 560-point maximum used for overflow. Added a dedicated 480-point tier.
- **P1:** The Safety summary preceded and visually dominated the changes. Replaced routine copy with one secondary Beta line, count chips, and changes-first operation cards.
- **P1:** Omissions and validation were always expanded and duplicated the same underlying unavailable-target reasons. Moved all secondary review sections into one disclosure.
- **P2:** Korean preview contained the English ColorSync inactive-display message. Added an exact Korean localization.

### Iteration 2

- **P2:** After compaction, a 500-point preview left a large blank tail below the action row. Reduced the initial content height to 440 points and used viewport minimum height so short-state actions remain bottom-aligned while overflow retains the established scroll sequence.
- **P2:** The new tray evidence inherited a synthetic apply-result banner that was absent from the user reference. Added a no-summary three-profile fixture so the comparison measures the requested empty-tail state rather than transient feedback.

### Final visual QA

The build-local comparison artifacts use exact normalized widths and top alignment:

- tray: 368×560 source beside a 368×480 implementation padded to the same 560-point comparison height;
- Apply Preview: 620×500 source beside a 620×440 implementation padded to the same 500-point comparison height.

The final comparison shows the tray's large empty tail reduced by about 70 points. Apply Preview now exposes all two changes and both before → after values in the first scan, while the two omissions and two validation messages are summarized in one collapsed row. No visible English ColorSync sentence remains in the Korean fixture. Standard, dark, minimum, and accessibility-text fixtures retain opaque output and scrollable access to overflow content.

Final severity result: no open P0, P1, or P2 visual issue in the synthetic scope.

## Verification status

Focused geometry, controller, workflow policy, localization, safety-source, and offscreen evidence selections pass. The canonical non-live `make verify` also passes: 194 XCTest cases, 333 Swift Testing cases across 39 suites, one isolated native popover regression, 4,820 release-tooling assertions, lint/localization policy, Swift Debug/Release, universal Xcode Debug/Release, Analyze, package, checksum, and mounted `arm64+x86_64` verification. `git diff --check` passes. The resulting local unsigned development DMG SHA-256 is `6a77ad1f830f30faa620a1e6f29ab1f9fb035c43ad43b9e6426ddcc58b355cff`; its executable SHA-256 is `6b1b6feda3b886de30b5cbd2cc78117682c4d5e14d0d0932b53bb1bd0e5da260`.

Behavior-focused implementation commit `30b50b1` records this verified source and evidence. Optional reinstall evidence remains deliberately pending until it exists and can be recorded without overstating completion.

Installed focus order, real accessibility settings, full keyboard traversal, VoiceOver, multi-display placement, and every hardware apply/rollback path remain outside this synthetic result.
