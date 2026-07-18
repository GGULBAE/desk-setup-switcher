# Release evidence template

Complete one protected approval record from this template for each public release. A sanitized copy may be committed under `docs/evidence/releases/<version>/` once a real candidate exists; files under `docs/releases/` are curated Release notes, not proof. A checked box is a claim backed by the linked evidence for the exact final candidate; intent, a command transcript from another build, historical ad-hoc evidence, or an empty search is not enough.

Follow [Distribution](DISTRIBUTION.md), [Governance](../GOVERNANCE.md), the [support matrix](SUPPORT-MATRIX.md), and the [incident runbook](RELEASE-INCIDENT-RUNBOOK.md). Never record credentials, real SSIDs, exact locations, IP host addresses, home paths, serial numbers, personal device identifiers, raw profiles, or unredacted diagnostics.

## Release status

| Field | Recorded value |
| --- | --- |
| Status | Not approved / protected draft / approved / published / affected / discontinued |
| Version and tag | `<not recorded>` |
| App version and build number | `<not recorded>` |
| Commit | `<not recorded>` |
| Release operator | `<not recorded>` |
| Release approver | `<not recorded>` |
| Candidate created at | `<not recorded>` |
| Canonical Release URL | `<not recorded>` |
| Canonical site URL | `<not recorded>` |

## Candidate freeze and verification

- [ ] The tag equals `v` plus `CFBundleShortVersionString`; `CFBundleVersion` is a positive candidate-unique build number.
- [ ] The commit and submodules/dependencies are fixed, the checkout is complete and non-shallow, and the worktree is clean.
- [ ] `make verify`, `make audit-public-release`, and `git diff --check` pass on that commit.
- [ ] Remote CI passes the required checks for that exact commit.
- [ ] Initial public support remains Apple Silicon on macOS 14 or later; no Intel runtime claim is present.
- [ ] Release entitlements are reviewed, minimal, recorded below, and omit `com.apple.security.get-task-allow`.

| Evidence | Value or link |
| --- | --- |
| Toolchain: macOS/Xcode/Swift/SDK | `<not recorded>` |
| Verification run and counts | `<not recorded>` |
| Remote CI run | `<not recorded>` |
| Release entitlement manifest/hash | `<not recorded>` |
| Supported architecture/deployment target evidence | `<not recorded>` |

## One-candidate lineage

The release app is built once. Signing, packaging, notarization, and stapling may change signatures and DMG bytes but must not rebuild or change the app. A rebuild, resource change, entitlement change, executable change, or build-number change creates a new candidate and invalidates every downstream row and beta report.

| Identity | Recorded value |
| --- | --- |
| Signed executable SHA-256 | `<not recorded>` |
| Signed app CodeDirectory hashes, keyed by `arm64` and `x86_64` | `<not recorded>` |
| Designated requirement | `<not recorded>` |
| Developer ID authority and Team ID | `<not recorded>` |
| Hardened-runtime flags and secure timestamp | `<not recorded>` |
| Effective entitlements | `<not recorded>` |
| Signed-app resource manifest/hash | `<not recorded>` |
| Pre-notarization signed DMG SHA-256 | `<not recorded>` |
| Notary submission ID and `Accepted` result | `<not recorded>` |
| Redacted notary log/hash | `<not recorded>` |
| Final post-staple DMG SHA-256 | `<not recorded>` |
| Final checksum file/hash | `<not recorded>` |
| SBOM filename/hash | `<not recorded>` |
| Release manifest filename/hash | `<not recorded>` |
| DMG provenance bundle filename/hash and verified subject digest | `<not recorded>` |
| DMG SPDX 2.3 SBOM bundle filename/hash, predicate type, and verified subject digest | `<not recorded>` |
| Release-manifest provenance bundle filename/hash and verified subject digest | `<not recorded>` |

- [ ] The app and DMG pass strict `codesign` verification.
- [ ] The notary result was parsed as `Accepted`; command exit alone was not used as proof.
- [ ] The final DMG passes stapler validation and Gatekeeper assessment.
- [ ] The app mounted from the final DMG passes Gatekeeper assessment and matches the signed executable, both architecture-labelled CodeDirectory hashes, designated requirement, entitlements, and resource manifest above.
- [ ] No rebuild or app-bundle change occurred between the recorded release build and the final stapled DMG.

## Protected remote controls and draft

| Control | Evidence link or read-only result |
| --- | --- |
| Default-branch protection and required CI | `<not recorded>` |
| Release-tag restriction | `<not recorded>` |
| Protected `release-candidate` environment | `<not recorded>` |
| Required reviewer and bypass policy | `<not recorded>` |
| Environment-scoped signing/notary credentials present | `<not recorded; never record values>` |
| Private vulnerability reporting enabled/tested | `<not recorded>` |
| Immutable releases enabled | `<not recorded>` |
| Protected workflow run and artifact ID | `<not recorded>` |
| Protected draft Release URL/ID | `<not recorded>` |

- [ ] A read-only query proves the effective remote workflow cannot publish an unsigned artifact or bypass approval.
- [ ] The protected draft contains exactly the nine assets below. Curated English/Korean notes are the Release body, not a tenth asset.
- [ ] All nine assets were downloaded again byte-for-byte; hashes and signatures match this record, and all three attestation bundles verify their exact subjects.
- [ ] Immutable releases are enabled before publication.

| Exact draft asset | Purpose and recorded verification |
| --- | --- |
| `Desk-Setup-Switcher-<version>.dmg` | Final signed, notarized, stapled candidate and SHA-256 |
| `Desk-Setup-Switcher-<version>.dmg.sha256` | One-entry checksum file and recomputation |
| `Desk-Setup-Switcher-<version>.spdx.json` | Exact-candidate SPDX 2.3 SBOM and hash |
| `release-manifest.json` | Candidate/run/lineage/evidence manifest and hash |
| `notary-result.json` | Sanitized accepted result and hash |
| `notary-log.json` | Sanitized log bound to submission ID, archive, and pre-notary DMG hash |
| `Desk-Setup-Switcher-<version>.provenance.sigstore.json` | Final-DMG provenance bundle and verified subject |
| `Desk-Setup-Switcher-<version>.sbom.sigstore.json` | Final-DMG SPDX 2.3 SBOM attestation bundle and verified subject |
| `release-manifest.provenance.sigstore.json` | Release-manifest provenance bundle and verified subject |

## Exact downloaded/quarantined lifecycle

Record each result separately. Use synthetic data and the exact final DMG above. No row may reuse historical ad-hoc or other-build evidence.

| Required result | Evidence link | Pass |
| --- | --- | --- |
| Browser-download archive and extracted-DMG `com.apple.quarantine` value recorded before open; attribute was neither added nor removed | `<not recorded>` | [ ] |
| Final DMG SHA-256 and final-DMG provenance attestation match | `<not recorded>` | [ ] |
| Gatekeeper identifies the Developer ID publisher; no Open Anyway workaround | `<not recorded>` | [ ] |
| Clean first launch and menu-bar-only lifecycle | `<not recorded>` | [ ] |
| Launch at login is off by default; any optional opt-in is explicit | `<not recorded>` | [ ] |
| Capture → Edit → Review explanation works without applying a setting | `<not recorded>` | [ ] |
| Upgrade from recorded predecessor build preserves schema-1 profiles, settings, selection, backups, and consent boundary | `<not recorded>` | [ ] |
| Synthetic schema 0→1 migration and last-known-good creation | `<not recorded>` | [ ] |
| Synthetic primary corruption recovers the last-known-good backup and quarantines safely | `<not recorded>` | [ ] |
| Import replacement and exclusive/no-overwrite export | `<not recorded>` | [ ] |
| Diagnostics browse, refresh, clear, and redaction boundary | `<not recorded>` | [ ] |
| Uninstall after disabling login item | `<not recorded>` | [ ] |
| Optional app-owned data/preferences removal, with external exports preserved | `<not recorded>` | [ ] |

## External beta and release blockers

Every report must follow [the external beta template](EXTERNAL-BETA-REPORT-TEMPLATE.md), use the same final DMG SHA-256 and final-DMG provenance attestation, run on Apple Silicon/macOS 14+, preserve real quarantine, and avoid live system-setting mutation unless separately authorized.

| Report | Tester record | Final DMG SHA matches | DMG provenance matches | Mandatory lifecycle passes | Open P0/P1 |
| --- | --- | --- | --- | --- | --- |
| Beta 1 | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 2 | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 3 | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |

- [ ] A read-only public issue query shows zero unresolved P0/P1 issues for this candidate.
- [ ] The maintainer records zero unresolved product P0/P1 blockers.
- [ ] The security responder records only a yes/no statement that no confidential P0/P1 blocker remains; no private count or detail is published.

## Public surface and approval

- [ ] The final support matrix preserves exact verification levels and Apple Silicon-only support.
- [ ] README, English/Korean guides, SECURITY, SUPPORT, privacy, checksums, site, and release notes agree.
- [ ] The bilingual site passes deployed no-tracking/no-cookie and clean-session link checks.
- [ ] Repository description, topics, Homepage, and social preview match the approved copy.
- [ ] The release approver explicitly approves the final artifact, tag, notes, publication, and site.
- [ ] The maintainer separately approves each promotional post.
- [ ] After publication, all nine assets are re-downloaded and the final hash/signature plus all three attestation bundles still match.

| Approval | Approver and evidence link | Recorded result |
| --- | --- | --- |
| Candidate and evidence | `<not recorded>` | Not approved |
| Tag and immutable Release publication | `<not recorded>` | Not approved |
| Site and repository metadata | `<not recorded>` | Not approved |
| English/Korean launch posts | `<not recorded>` | Not approved |

## Post-release Homebrew own-tap gate

GitHub Releases remains canonical. Keep Homebrew documented as “not offered” until all four rows pass against the public final SHA-256. Official Homebrew Cask submission is a later non-goal.

| Own-tap result | Evidence | Pass |
| --- | --- | --- |
| Clean install | `<not recorded>` | [ ] |
| Upgrade | `<not recorded>` | [ ] |
| Uninstall without unrelated deletion | `<not recorded>` | [ ] |
| `zap` removes only documented optional app-owned data | `<not recorded>` | [ ] |
