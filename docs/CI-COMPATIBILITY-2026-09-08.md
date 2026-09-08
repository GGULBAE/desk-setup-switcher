# CI compatibility follow-up — 2026-09-08

## Scope

The user approved continuing after the site dependency refresh exposed independent public-history audit and macOS 15 offscreen-test failures. This follow-up does not change product layout, profile semantics, live adapters, login-item registration, or installed applications. It does not deploy the site or publish a release. Existing unrelated Apply Preview and documentation edits remain outside the intended commit.

## Public-history review

The scanner intentionally approves only exact Git blob, repository path, and finding-category tuples. Source edits invalidate approval even when the fixture data is unchanged. All fifteen flagged historical blobs were reviewed with their surrounding source:

| Path | Revisions | Finding and review |
| --- | ---: | --- |
| `Sources/DeskSetupSwitcher/UIAuditFixtures.swift` | 1 | Subnet mask beside documentation-only manual IPv4 addresses in a synthetic snapshot. |
| `Tests/DeskSetupCoreTests/ProfileApplicabilityNormalizerTests.swift` | 4 | Subnet mask in a constructed profile using documentation-only addresses and an invalid-domain proxy. |
| `Tests/DeskSetupSystemTests/VisibleSettingEndToEndInvariantTests.swift` | 3 | Subnet masks in injected mock network configurations and mock rollback expectations. |
| `Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift` | 7 | Short fake audio-role names in injected capability catalogs; the final revision adds current/saved/unreadable roles for mute read-back cases. |

Fourteen revisions reuse values already present in reviewed blobs. The remaining revision's added role names are explicitly constructed test identifiers, not identifiers captured from a device. No credentials, personal hosts, or real hardware identity is approved. The exact tuple entries are in the scanner; there is no new generic safe-word rule, path allowlist, or blanket network-mask exemption.

Three new fixture assertions prove that current reviewed files pass, a harmless content edit fails, and copying identical bytes to a different path fails. Existing negative probes and output redaction checks remain. The audit regression script's own updated exact blob is reviewed for its existing runtime-assembled IP/SSID probes.

## macOS rendering compatibility

The earlier CI run's seven issues assumed one native button width, fixed tray action glyph coordinates, and a fixed-color Sound scan ending at a hard-coded vertical position. Native control metrics and GroupBox rendering differ across macOS releases.

Debug-only layout anchors are enabled only by the existing synthetic audit configuration. They propagate actual SwiftUI child and parent bounds to an offscreen test host; release builds return the original view. They do not request screen/accessibility permissions, automate UI, persist evidence automatically, or call system adapters.

Revised assertions retain:

- Three tray card surfaces, bounded bottom whitespace, visible action pixels, aligned action centers, separated buttons, and an actually blank reserved caption region.
- Output and Input as separate, fully visible sections, with device/volume/mute rows contained in Output and device/volume rows contained in Input, non-overlapping fields, and visible field pixels.
- Two separated sidebar controls, intact rendered labels contained by their control bounds, and centered action alignment; no arbitrary native button-width minimum.
- Existing language, accessibility structure, large text, color/contrast, safe-area, and read-only routing checks.

New tests prove opt-in isolation, real offset measurement, parent/child anchor preservation, and rejection of empty, clipped, or detached geometry. Virtual offscreen accessibility-tree limitations remain; this is not assistive-technology or live-hardware certification.

### macOS 15 follow-up from the first pushed run

[Run 34237761875](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/34237761875), for `56a7194`, passed the complete site job on Node 22.13.0, including zero registry advisories and all three 11-test build states. Sound grouping/viewport and label-containment assertions passed on macOS 15. Four app issues remained: one absolute-darkness label sample and three strict gap comparisons where the measured gap was exactly 20 points.

The follow-up samples actual label bounds, excluding native button decoration, and detects both dark-on-light and light-on-dark ink against the label's dominant background. It retains nonempty pixel evidence and the six-point ink-center alignment tolerance; there is no OS-specific skip. Deterministic bitmap tests reject blank/nearly-flat regions and accept faint disabled or inverted text. The 20-point sidebar minimum now uses the exclusive `CGRect.maxX` boundary correctly; the existing pixel-run gap assertion remains unchanged. This is layout evidence, not a new disabled-text contrast certification.

## Verification status

Local host: macOS 26.6.2. CI: macOS 15, with Node 22.13.0 for the site job. Local and remote evidence are not interchangeable.

- Targeted layout/offscreen tests: passed six tests, including final viewport-containment assertions.
- `make audit-public-release`: passed 42 fixture assertions and full history/privacy/asset-metadata scanning.
- Isolated intended-source `make verify`: passed 357 tests in 40 suites, the separately run native popover test, release-tooling mocks, both architecture builds/static analysis, and unsigned package/resource verification. Unrelated working-tree edits were absent from this checkout.
- Clean site install, `npm run audit:dependencies`, and `make verify-public-surface`: passed, with zero registry advisories and 11 tests for each holding/published/restored-current state.
- Final lint, JavaScript syntax, and `git diff --check`: passed. Only the scoped changes are staged; existing unrelated edits remain in the working tree.
- Remote macOS 15/Node 22.13.0 evidence is the [CI check attached to the resulting commit](https://github.com/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml), checked after push. It is not inferred from local macOS 26 results.

The above local counts describe the initial compatibility commit. The label-contrast/gap follow-up was reverified in an isolated intended-source checkout: `make verify` passed 358 tests in 40 suites, the separate native popover test, release-tooling mocks, dual-architecture builds/static analysis, and unsigned package/resource verification. `make audit-public-release` passed all 42 fixture assertions and the full scan. The dependency audit still reports zero registry advisories, and `make verify-public-surface` passed all three 11-test build states. These are local results; exact-commit macOS 15 CI must pass before the follow-up is closed.

## Next bounded task

After these gates pass, use the exact approved release candidate to gather the remaining physical Apple Silicon/macOS 14 installation and lifecycle evidence. Do not add features, change distribution trust claims, publish, or run live setting mutations without their separate explicit approval/preflight/rollback procedure. Completion requires evidence tied to candidate bytes and current README/support/ledger status.
