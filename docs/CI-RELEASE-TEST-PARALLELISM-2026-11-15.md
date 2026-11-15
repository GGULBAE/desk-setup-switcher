# Release-tooling CI concurrency — 2026-11-15

## Purpose and measured baseline

The user requested shorter CI while retaining every existing check. The previous exact-source [CI run 43691766387](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/43691766387), commit `3911c8d3ee03dccfddaba3b93021cbff339d6606`, spent 50m46s in `make verify`, followed by 7m29s in `make audit-public-release`. Its app job ran about 59 minutes. The serial release-tooling stage accounted for about 40m10s; publication, remote-controls collection, and legacy containment were the largest independent suites.

## Change and execution contract

`scripts/release/test-release-tooling.sh` retains its complete suite inventory, and `run_test_suites.rb` schedules those existing files as separate processes. The default is four concurrent suites. `DESK_SETUP_RELEASE_TEST_JOBS=1` uses the same complete inventory serially; canonical integers 1–8 are accepted, and invalid limits fail before suite launch.

Each suite receives its own owner-only temporary directory and output log. Shell and Ruby suites retain their existing mock commands, private repositories, synthetic fixtures, and assertions. The pool only controls when the suite process starts. It waits for every registered suite even after another fails, preserves each suite's stdout/stderr, and returns failure for nonzero exits, signals, and spawn failures. INT/TERM stops active process groups and waits for cleanup before removing temporary files; cancellation returns a nonzero signal-derived status.

The remaining shell checks run after the whole pool succeeds. Their source, order, and failure behavior are preserved. Swift/AppKit tests, native popover isolation, warnings-as-errors builds, both Xcode architectures/configurations, analysis, packaging/checksum/bundle checks, public-history/privacy/asset audits, and site/dependency checks retain their existing commands and workflow gates. No workflow permission, trigger, cache, timeout, installed app, or live setting is changed.

## Existing coverage inventory

All 15 suite files below are byte-identical to the baseline. Their expected summaries are the preceding successful CI results, not new hardware evidence.

| Existing suite | Tests, when separately reported | Assertions |
|---|---:|---:|
| `test_release_policy.rb` | 50 | 374 |
| `test_remote_controls_policy.rb` | 131 | 659 |
| `test_remote_controls_policy_v2.rb` | 55 | 210 |
| `test_remote_controls_policy_v3.rb` | 23 | 86 |
| `test_remote_controls_collector_v2.rb` | 14 | 71 |
| `test_remote_controls_collector_v3.rb` | 10 | 17 |
| `test_publication_policy.rb` | 80 | 407 |
| `test_external_beta_policy.rb` | 165 | 1,386 |
| `test_verify_app_bundle.sh` | — | 8 |
| `test_remote_controls_collector.sh` | — | 132 |
| `test_release_evidence_history.sh` | — | 19 |
| `test_prepare_draft_release.sh` | — | 57 |
| `test_restore_candidate_artifact.sh` | — | 261 |
| `test_publish_approved_release.sh` | — | 557 |
| `test_legacy_workflow_containment.sh` | — | 306 |
| Existing parent shell checks | — | 270 |

The baseline has 4,820 assertions across these release-tooling checks. The coordinator regression suite adds 41 assertions and its parent adds one exit-status assertion, for an expected 4,862. The parent summary becomes 271, retaining its original 270. Swift's 387 tests and the public-history audit's 42 fixture assertions remain separate counts.

## Coordinator regressions and verification status

`test_run_test_suites.rb` uses actual child processes, file-lock state, and readiness barriers to prove overlap without a speed threshold. It compares serial and parallel outcomes, checks that every registered suite runs once despite a failure, verifies private temporary-directory cleanup and exact stdout/stderr preservation, exercises spawn and signal failures, rejects empty/duplicate inventories, and interrupts the actual CLI with INT and TERM while checking child/grandchild termination.

The focused 41 coordinator assertions passed during implementation. Full local verification, unchanged-summary comparison, and exact-source CI timing are recorded at the corresponding completion checkpoints. A performance claim requires the successful CI result; elapsed time can vary with runner load. The baseline and candidate use the same macOS workflow and no restored build/test cache.

Local `make verify` subsequently completed with exit code 0: 387 Swift tests, the isolated native popover, all 15 original release-suite summaries, 271 parent shell assertions, warnings-as-errors Debug/Release builds for both architectures, static analysis, and DMG/bundle/resource checks passed. The 15 suite summaries matched the baseline individually; the original 4,820 release assertions plus 42 new coordinator/parent assertions total 4,862. Public-history audit and remote CI remain the subsequent pre-push/completion checkpoints for this source snapshot.

## Boundaries

This changes development test scheduling only. No suite is filtered out, cached as already passed, marked optional, retried to hide a failure, or given a weaker assertion. Existing user changes remain outside the commit. No app release, site deployment, local reinstall, settings mutation, or hardware-support promotion is part of this work.
