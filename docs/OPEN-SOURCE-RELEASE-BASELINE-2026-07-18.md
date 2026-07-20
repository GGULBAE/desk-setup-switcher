# Open-source release baseline audit

Date: 2026-07-18

> **Superseded audit snapshot:** This document preserves the first local baseline at its audit point; it is not the current release-status ledger. In particular, the CI/release-workflow bullets below describe an unpushed local proposal, while the workflow effective on `origin/master` still exposes an unsigned public-release path for `v*` tags. Use [COMPLETION-CRITERIA.md](COMPLETION-CRITERIA.md) and [DISTRIBUTION.md](DISTRIBUTION.md) for the current mandatory boundary. No release tag may be pushed until the remote path and protections are replaced and verified.

## Outcome

The first local open-source release baseline is complete. This pass hardened profile storage and import boundaries, changed launch at login to explicit opt-in, added complete-history and image-metadata auditing, and made the repository's support, security, compatibility, governance, and distribution claims internally consistent.

This is development evidence, not a public release. No tag, GitHub Release, signed or notarized artifact, Homebrew cask, demo site, announcement, or supported download was created. No display, audio, network, login-item, TCC, mouse, keyboard, or Keychain mutation was run during this pass.

## Product boundary

The public-beta product remains a local-only menu-bar app with one deliberate journey:

1. Capture current settings without changing the Mac.
2. Edit a saved profile.
3. Review proposed changes and explicitly apply them.

There is no account, cloud service, telemetry, analytics, automatic profile switching, in-app updater, arbitrary shell execution, UI automation, private API, or third-party application configuration. Full-app VoiceOver certification is outside the release goal and is not claimed. Keyboard behavior, accessibility names and values, and non-color state cues remain required product quality.

## Fixed release identities

The planned `v0.1.0` public-beta baseline fixes these identities:

| Boundary | Fixed value or policy |
| --- | --- |
| App version | `0.1.0` |
| Build number | `1`; increase globally for every new Developer ID candidate; only exact origin-artifact restoration may reuse it |
| Bundle identifier | `dev.ggulae.desk-setup-switcher` |
| Keychain service | `dev.ggulae.desk-setup-switcher.secrets` |
| Deployment target | macOS 14.0 or later |
| Planned initial CPU boundary | Apple Silicon; the packaged `x86_64` slice is cross-built but physically unverified, and support still requires the exact-candidate gates |
| Profile interchange | `schemaVersion: 1` for the `0.1.x` line |
| Swift package products | Internal and unstable; not a supported SDK or plug-in API |
| Versioning | Immutable `v`-prefixed SemVer tags; published assets are repaired with a new patch version |

The complete compatibility policy is in [COMPATIBILITY.md](COMPATIBILITY.md).

## Changes in this baseline

### Explicit launch-at-login consent

- A fresh install remains unregistered until the user enables launch at login in Settings.
- A stored setting is preserved only after the current consent marker exists.
- Pre-release state cannot prove that a previous registration was voluntary because older builds attempted registration automatically. The first run of this baseline resets that old setting to off and removes a stale registration.
- Deterministic tests cover fresh-off, opt-in, opt-out, consented-state preservation, approval state, and pre-release migration. No live `SMAppService` call was made.

### Profile storage and import boundaries

- Store filenames reject traversal and reserved forms before file access.
- Profile reads reject symbolic links, non-regular files, unexpected owners, oversized input, and source replacement or in-place mutation during the read.
- File operations use no-follow descriptor checks and compare device/inode/owner identity before sensitive chmod, migration, recovery, or quarantine actions.
- Corrupt-file quarantine uses non-overwriting rename semantics, validates the moved identity, and attempts source restoration if the move cannot be proven safe.
- New profile data is written to a private staging file, synchronized, and atomically renamed. Parent-directory synchronization is best effort.
- UI storage errors remain sanitized and unrelated features remain available when safe.

The focused storage/import suite passed 53 tests. Independent security review found no P0 or P1 release blocker.

Accepted P2 boundaries are intentionally recorded rather than hidden:

- A precisely timed same-user process replacing a higher ancestor remains best effort; the app-owned store assumes one trusted writer.
- Migration and backup recovery retain a narrow identity-check-to-rename window without cross-process locking.
- Export uses an exclusive final-file write and a crash could leave a partial new export; a staged non-overwriting rename is a future hardening pass.
- Parent-directory sync is best effort, so perfect sudden-power-loss durability is not claimed.

These bullets preserve the 2026-07-18 implementation boundary. The current writer described in the completion ledger later moved managed staging, commit, rollback, cleanup, and sync onto one verified parent-directory descriptor and added deterministic parent-path, regular/symlink leaf replacement, and both post-commit rollback tests. Current residuals include the lack of public inode-conditional rename/unlink and possible private old-leaf staging residue after abrupt interruption between swap and unlink; there is no production path-based mutation fallback.

### Repository and release controls

- `make audit-public-release` now requires complete Git history and inspects historical source paths plus PNG, JPEG, and icon metadata for high-confidence credential and personal-path patterns without printing matched secret values. A later hardening follow-up also scans commit and annotated-tag author, committer, and tagger email metadata without printing identity values.
- Already-public legacy personal email metadata remains in immutable history; no history rewrite or remote mutation was performed. Only exact reviewed commit SHAs that are ancestors of the fixed public baseline may pass the value-free exception file. Every other commit and annotated tag, including synthetic fixtures, requires a GitHub noreply identity. Replacement refs and grafted history fail closed, and annotated-tag traversal starts from every ref and follows nested tag objects.
- The local CI proposal fetches full history and runs the public-release audit; it was not yet effective on the remote default branch at this snapshot.
- The then-local tag-workflow proposal was constrained to an unsigned **draft prerelease candidate** in the named `release` environment. It was not the effective remote workflow and could not establish a supported or canonical release. The effective `origin/master` workflow, inspected read-only on 2026-07-18, can publish an unsigned Release from a `v*` tag and remains a publication blocker.
- Support, security, privacy, governance, compatibility, contribution, and distribution documents now state the same public-beta boundary.

The 2026-07-18 read-only repository-settings review found that the actual `release` environment, default-branch protection, and private vulnerability reporting are not configured. Workflow YAML does not substitute for those controls. They remain publication blockers.

## Verification evidence

`make verify` completed successfully on 2026-07-18 with warnings treated as errors:

- 173 XCTest checks;
- 322 Swift Testing checks across 40 suites; and
- one isolated native `NSPopover` regression.

Total: **496 checks**.

The same gate passed localization and source-policy lint, Swift Debug and Release builds, universal Xcode Debug and Release builds, Xcode Analyze, project-generation verification, DMG/checksum creation, and mounted-image metadata, English/Korean resource, architecture, and ad-hoc signature checks.

Development-only universal DMG SHA-256:

`961f4044996c0f5fc0b4e8e782355da4d620c553e4c1891918d19323f6d67eac`

The filename contains `unsigned` and the app has only an ad-hoc integrity signature. This hash does not identify a Developer ID-signed, notarized, stapled, Gatekeeper-verified, supported, or published artifact. The package was not installed or launched in this pass.

The complete-history and asset-metadata audit also passed locally. A later follow-up passed 38 synthetic audit assertions plus the current-history audit, including value-suppressed commit/tag identity enforcement, exact-SHA-only legacy exceptions, all-ref/nested annotated-tag coverage, and replacement-ref/graft rejection. This scoped automation does not OCR historical pixels. Historical installed and UI evidence remains historical and must not be presented as evidence for this newly built package.

## Remaining public-launch gates

The open-source launch goal remains active. Public approval requires all of the following:

- rewrite the user-facing README and publish concise English and Korean install, use, permissions, recovery, uninstall, contributor, schema, and adapter guides;
- create a static bilingual, no-tracking demo site and redacted screenshots/video or GIF assets;
- configure protected default-branch and `release` environment controls and enable/test private vulnerability reporting;
- implement one-candidate Developer ID signing, hardened runtime, secure timestamp, notarization, stapling, app/DMG Gatekeeper assessment, SBOM, and provenance/attestation;
- re-download and re-verify the exact protected draft assets;
- pass clean-quarantine installation and upgrade checks on Apple Silicon with at least three external beta testers and no unresolved P0/P1 issue;
- synchronize the final site, README, release notes, support matrix, and checksums; and
- obtain explicit maintainer approval before publishing a tag, release, site announcement, or promotional post.

Homebrew follows a successful canonical notarized GitHub Release. An own tap comes first; an official Homebrew Cask submission is a later milestone.
