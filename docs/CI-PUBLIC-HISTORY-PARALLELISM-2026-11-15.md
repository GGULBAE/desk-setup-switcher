# Public-history audit concurrency — 2026-11-15

## Goal and baseline

Run the public-history audit alongside app verification while keeping every existing check and approval condition. The preceding successful [CI 43706480020](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/43706480020), source `800757a32903e7dc3b0e02c6e8ff2fa90b266f8e`, took 38m44s: `make verify` used 30m51s and the subsequent public-history audit used 7m37s. New performance claims require a successful exact-source CI comparison.

## Execution and approval contract

`make verify-ci` calls `scripts/release/verify_ci.rb`, which schedules exactly the original complete `make verify` and `make audit-public-release` commands in two isolated processes. The original app verification script, audit scanning rules, 42 existing audit fixtures, and production release/approval policies are unchanged. A later bounded Git transport correction and four additional transport assertions are recorded below. Every check still runs; neither result is optional or cached as already passed.

Both commands must exit successfully. Source roots must resolve to their own Git checkout, be non-shallow, and match the pinned commits before and after execution. Hosted CI also checks that tracked files remain clean. Missing roots, parent-Git fallback, invalid event/commit inputs, source drift, either command failure, or interruption returns failure and blocks the existing upload step.

The existing `Verify macOS app` and `Verify public site and release assets` jobs remain the only two jobs. Job IDs/names, permissions, triggers, concurrency policy, runner/timeouts, pinned actions, public-site checks, artifact files, error-on-missing behavior, and retention remain intact. No `always()` or `continue-on-error` bypass is added to verification or upload.

## Pull request source isolation

The app still tests GitHub's checked-out merge source. Before verification starts, the pinned checkout action fetches the original `github.event.pull_request.head.sha` with full history and no persisted credentials into `.build/public-history-audit`. The audit runs from that root and must match the event's head SHA. Push and workflow-dispatch audits use the same pinned source as the app.

The hidden `.build` location keeps the second checkout outside the existing Markdown traversal and tracked-source audit enumeration. The app scripts write only their own Swift/Xcode build subdirectories and artifact staging directories; they do not clean this checkout during verification. The audit still inspects every tracked file, stage-0 index byte, reachable history object, identity, and asset category required by the unchanged scanner. Its existing `.build` exclusion is not expanded.

## Process cleanup and diagnostics

The existing bounded process runner retains its release-suite defaults and 41 regression assertions. CI uses distinct labels and logs for the app and audit. Cancellation waits for process groups after their leaders exit, allowing nested release-test coordinators to stop their own groups before cleanup. The CI parent provides five seconds of cancellation grace around the existing two-second nested cleanup; workflow, fixture, production freshness, and ordinary verification timeouts are unchanged. Signal-derived failure cannot permit upload.

## Verification inventory

- The original 15 policy/mock suite files and their 4,550 assertions remain unchanged from the baseline.
- The previous 41 process-runner assertions and all 271 parent assertions remain; a sixteenth CI-gate suite adds 59 assertions and one parent exit assertion. Total release assertions become 4,922, preserving all previous 4,862.
- The 387 Swift tests, native-popover isolation/host condition, warnings-as-errors builds, both architectures/configurations, analysis, packaging/bundle/resource checks, public-history scanner and 42 fixtures, dependency advisory audit, and public-surface checks retain their existing commands and conditions.
- `test_verify_ci.rb` uses real Git checkouts and process barriers. It proves actual app/audit overlap, exact PR head versus merge working directories, private temp cleanup and output preservation, app/audit/both failure blocking, pre/post source checks, invalid/missing/shallow roots, and cancellation through a nested process group that ignores TERM.
- Workflow contract assertions preserve the exact two required check names, read permission, event triggers, PR checkout/ref/credential settings, aggregate-gate-before-upload order, and artifact inventory/retention.

The existing parent workflow assertions also retain their count and approval conditions. Their literal expectations are updated for the hidden checkout path and combined step: the PR ref/condition/action/full-history/credential checks remain, and the combined command must select the event head for PRs or current commit for branches, run unconditionally, and precede upload without a bypass. The original serial-step names are replaced by assertions on the equivalent parallel contract.

The focused 59 CI-gate assertions and unchanged 41 runner assertions passed during implementation. Full local verification, README/link checks, new-commit public audit, and exact-source whole CI are the completion checkpoints. Measurements use the earliest job start through final job completion, excluding queue time, and remain subject to runner load.

## Initial local completion checkpoint — 2026-11-16

For initial source `4237c9454da5676c0ee0b210d7e1ac317b8b3d2c`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make verify-ci` completed with exit code 0. Both unchanged complete commands passed, followed by the source-anchor check. The log comparison confirmed each original suite's test/assertion summary, all 4,922 release assertions, 387 Swift tests, the locally executed isolated native popover, universal Debug/Release builds, static analysis, and DMG/checksum/bundle/resource verification. The audit retained its 42 fixture assertions and complete history/privacy/asset scan.

`make verify-public-surface` passed its public-copy, release-link, asset, dependency/build, and rendered-site checks. The dependency advisory audit reported zero vulnerabilities. All 42 local Markdown/HTML README references and image alternative text were checked, and the documented combined command and upload condition match the implementation. Final worktree and staged diff checks passed; unrelated tracked and untracked user changes remained unchanged.

The earlier local attempt exposed the parent's old serial-step/path expectations after all child suites and the audit had passed. Those expectations were adapted to the equivalent parallel approval contract described above, preserving their assertion count. The final full run above includes those corrected checks. A subsequent resumed session could not recover the old temporary log, so this complete run was executed again rather than inferred from the interrupted attempt. New-commit public auditing, push, exact-source full CI, and remote timing remain the delivery checkpoints; local timing is not a remote performance claim.

## Hosted timeout and bounded Git transport — 2026-11-16

Initial [CI 43790382387](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/43790382387), source `4237c94`, timed out at the unchanged 60-minute limit. Its public-site job passed in 3m00s. App verification itself passed in 1,983.39 seconds, including all 4,922 release assertions, 387 Swift tests, builds, analysis, and DMG verification. The audit never returned, and package upload remained blocked. This cancelled run is not a successful performance benchmark.

The scanner's two `git cat-file --batch` readers wrote the complete request inventory before reading responses. If the request and response pipes both fill, neither process can advance. Each reader now writes and flushes one object request, validates and drains its complete header/body/separator, then requests the next object. Every object/path/message and every existing validation and rejection remains in the same scan. No scanning rule, reviewed synthetic-blob approval, timeout, publication policy, or workflow approval condition changes.

`test-audit-batch-transport.rb` invokes the actual scanner and real Git through a strict transport guard. It rejects any second request until the previous response is fully consumed, independently of OS pipe capacity or elapsed time. The test first proves that its guard rejects the old write-ahead protocol, then checks scanner success, the full audit/diagnostic boundary, and both multi-object history and message streams. The uncorrected scanner failed this regression; the corrected scanner passed all four assertions. The original 42-assertion audit fixture file remains byte-identical and also passed. `make audit-public-release` adds this regression before the existing complete scan. Full local verification, README/public-surface checks, a new-commit scan, and successful exact-source CI must be repeated for the correction before reporting completion.

The corrected working tree subsequently passed complete `make verify-ci` with exit code 0: all 4,922 release assertions, 387 Swift tests, the local isolated native popover, universal builds, analysis, DMG/bundle/resources, the original 42 audit fixtures, all four new transport assertions, and the complete history/privacy/asset scan. `make verify-public-surface`, all 42 local README references and image alt text, the dependency advisory audit (zero vulnerabilities), and final diff checks passed. New-commit public auditing and exact-source hosted CI remain the final delivery checkpoints.

## Scope

This changes CI scheduling and adds approval regressions. App behavior, live settings, installed apps, public releases/site deployment, production approval policies, and hardware-support evidence are unchanged. Existing unrelated user edits stay outside the commit.
