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

First establish clean remote-master commit **A** with the two fresh
`final-pre-tag` manual JSON records defined by [the public release approval
contract](PUBLICATION-APPROVAL.md), then wait for exact-A CI. From a clean,
complete, non-shallow checkout of A, run
`make verify-remote-controls REMOTE_CONTROLS_EVIDENCE_OUTPUT=/absolute/private/remote-controls-final-pre-tag.json`
while remote `v*` refs and Releases are still empty. The parent directory must
be owner-owned mode 0700, the output path must be absent and outside the
repository, and the resulting mode-0600 bytes are exact external evidence
**E**. Create the annotated `v0.1.0` tag object locally against A with the exact
E digest-binding message, but do not push it. Create **B** as A's direct
single-parent child adding only unchanged E at
`docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json` as `100644`.
Integrate B without a merge commit, wait for exact-B CI, and rerun the A→B
semantic/history check. A separate authorization is required before the first
push of that already recorded tag object. E cannot be regenerated after local
tag creation. The verifier configures nothing, pushes nothing, and does not
authorize the later tag push.

- [ ] The tag equals `v` plus `CFBundleShortVersionString`; `CFBundleVersion` is a positive candidate-unique build number.
- [ ] The commit and submodules/dependencies are fixed, the checkout is complete and non-shallow, and the worktree is clean.
- [ ] `make verify`, `make audit-public-release`, and `git diff --check` pass on that commit.
- [ ] Remote CI passes the required checks for that exact commit.
- [ ] The planned initial target remains Apple Silicon with a macOS 14.0 deployment target; no Intel or unverified Sonoma runtime claim is present.
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
| Final gate output from `make verify-remote-controls REMOTE_CONTROLS_EVIDENCE_OUTPUT=…`, exact commit, all three candidate/draft, CI, and publication workflow blobs, one pinned CI run/check-suite ID, both required check-run IDs, and both required job IDs | `<not recorded>` |
| Release-tag creation rule and exact operator-only bypass | `<not recorded>` |
| No-bypass release-tag update/deletion rule | `<not recorded>` |
| Protected `release-candidate` environment | `<not recorded>` |
| Required reviewer and bypass policy | `<not recorded>` |
| `release-candidate-admin-bypass.json` ordinary blob, current phase, observer, protected source-bundle SHA-256 | `<not recorded; no raw screenshot>` |
| `release-publication-admin-token-scope.json` ordinary blob, current phase, observer, protected source-bundle SHA-256 | `<not recorded; no raw screenshot or token>` |
| Publication token type/owner/repository-only selection/expiry and exact five read permissions | `<not recorded; value never recorded>` |
| GitHub-hosted runner enforcement and runner image | `<not recorded>` |
| Environment-scoped signing/notary credentials present | `<not recorded; never record values>` |
| Secret child-environment isolation and direct-exec consumer checks | `<not recorded; result only>` |
| Ephemeral certificate/Keychain/notary-key cleanup result | `<not recorded; record result only, never paths or values>` |
| Catchable cancellation/tracked-child cleanup result | `<not recorded; result only>` |
| Private vulnerability reporting enabled/tested | `<not recorded>` |
| Immutable releases enabled | `<not recorded>` |
| Protected `build-candidate` origin run/attempt | `<not recorded; origin attempt must be 1 and never rerun>` |
| Immutable artifact ID/archive SHA-256 | `<not recorded; bind to the exact origin run>` |
| Separate `prepare-draft` verification run/attempt | `<not recorded; distinguish from candidate origin>` |
| Protected draft Release URL/ID | `<not recorded>` |

- [ ] A read-only query proves the effective remote workflow cannot publish an unsigned artifact or bypass approval.
- [ ] The two final-pre-tag records use protected screenshot/review-note bundles with visible phase/UTC challenge, false administrator bypass, distinct source SHA-256 values, exact policy operator, and no committed raw screenshot or token; then the final-pre-tag API verifier passes with zero drift and reports `manual_gates=2`.
- [ ] The recorded result came from `make verify-remote-controls REMOTE_CONTROLS_EVIDENCE_OUTPUT=/absolute/private/…`; direct `remote_controls_policy.rb` normalized-evidence output is offline component evidence and is not accepted as the final gate.
- [ ] The release manifest records `runner-environment=github-hosted`; each signing/notarization secret had one direct-exec consumer and was absent from unrelated child environments. The distinct admin-read token had exactly five bounded workflow uses, and the publication helper installed it only through five tracked, timeout-bounded GitHub read/download launcher call sites.
- [ ] The manifest contains `signedAppCompatibility` and `mountedAppCompatibility` records bound to the exact executable SHA-256. Both prove exactly `arm64,x86_64`, both slices report the repository-declared macOS minimum in `LC_BUILD_VERSION`, and the two records are identical.
- [ ] Normal completion and one catchable signing/notarization-cancellation probe confirm no decoded release credential or tracked notarization child remains. Do not claim shell cleanup for `SIGKILL` or host loss, and do not treat cleanup evidence as publication retry authorization.
- [ ] The immutable exact-nine-asset workflow artifact was finalized before the first Release mutation. Its ID/archive digest and attempt-1 origin run are recorded, and the origin build run was never rerun.
- [ ] The separate draft run proved the origin workflow/repository/commit/job/artifact metadata, downloaded the raw archive by ID, matched its SHA-256, extracted exactly nine regular files, and verified the signed candidate plus all three attestation bundles before mutation.
- [ ] If draft recovery ran, every pre-existing asset first compared byte-for-byte with that artifact, only missing names were appended without clobber, and no Release edit/delete/publication or tag mutation occurred. Record each draft attempt separately.
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
| Upgrade from recorded installable predecessor preserves schema-1 profiles, settings, selection, backups, and consent boundary, or validated first-beta lineage records not applicable | `<not recorded>` | [ ] |
| Synthetic schema 0→1 migration and last-known-good creation | `<not recorded>` | [ ] |
| Synthetic primary corruption recovers the last-known-good backup and quarantines safely | `<not recorded>` | [ ] |
| Import replacement and exclusive/no-overwrite export | `<not recorded>` | [ ] |
| Diagnostics browse, refresh, clear, and redaction boundary | `<not recorded>` | [ ] |
| Uninstall after disabling login item | `<not recorded>` | [ ] |
| Optional app-owned data/preferences removal, with external exports preserved | `<not recorded>` | [ ] |

## External beta and release blockers

Every report must follow [the external beta template](EXTERNAL-BETA-REPORT-TEMPLATE.md), use the same final DMG SHA-256 and final-DMG provenance attestation, run on Apple Silicon within the planned macOS 14+ matrix, preserve real quarantine, and avoid live system-setting mutation unless separately authorized. At least one accepted report must run the full exact-candidate lifecycle on macOS 14 Sonoma. The actual-byte candidate inventory, predecessor lineage, three closed JSON reports, and protected independence-review set described in [the lineage contract](PREDECESSOR-LINEAGE.md) must validate against the restored release manifest and provenance bytes; Markdown alone is not accepted evidence.

| Report | Tester record | macOS / coverage role | Final DMG SHA matches | DMG provenance matches | Mandatory lifecycle passes | Open P0/P1 |
| --- | --- | --- | --- | --- | --- | --- |
| Beta 1 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 2 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 3 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |

- [ ] At least one accepted report records Apple Silicon/macOS 14.x Sonoma and passes every mandatory exact-candidate lifecycle row.
- [ ] `candidate-inventory.json` records retained and non-retained prior protected runs in strictly increasing, unique build order, requires every completion to predate the current manifest, binds the current run/build, and carries the protected completeness-review receipt digest.
- [ ] `predecessor-lineage.json` v2 binds the actual inventory bytes and current candidate; the latest installable retained predecessor or the first-beta not-applicable state is consistent.
- [ ] `external-beta-set.json` binds the actual ordered bytes of `external-beta-01.json` through `external-beta-03.json`, identifies the Sonoma report, and records the protected no-PII independence review for three distinct external people.
- [ ] A read-only public issue query shows zero unresolved P0/P1 issues for this candidate.
- [ ] The maintainer records zero unresolved product P0/P1 blockers.
- [ ] The security responder records only a yes/no statement that no confidential P0/P1 blocker remains; no private count or detail is published.

## Public surface and approval

- [ ] The final support matrix preserves exact verification levels and Apple Silicon-only support.
- [ ] Before publication, the immutable Release body is self-contained and contains no branch-lifecycle document link; only the tag-pinned distribution procedure and exact support/advisory action routes are allowed.
- [ ] Before publication, the bounded public-copy finalization patch is reviewed locally but unpushed/unmerged, with its exact `master` base, resulting tree digest, and file allowlist recorded. After the immutable Release is visibly public, the unchanged patch synchronizes both publication records, README, the English/Korean guide index and guides, PRIVACY, SUPPORT-MATRIX, SECURITY, SUPPORT, and directly required status records.
- [ ] The finalization review head passes both exact CI jobs. Its protected merge is read back from `master`, has the reviewed tree digest, and one `master`-push run on that exact SHA passes exactly **Verify macOS app** and **Verify public site and release assets** before deployment.
- [ ] README, English/Korean guides, SECURITY, SUPPORT, PRIVACY, SUPPORT-MATRIX, checksums, both site publication records, the rendered site, and release notes agree, with no stale holding or disabled-private-reporting claim.
- [ ] The bilingual site passes deployed no-tracking/no-cookie and clean-session link checks.
- [ ] Repository description, topics, Homepage, and social preview match the approved copy.
- [ ] The release approver explicitly approves the final artifact, tag, notes, and Release publication. The synchronized public-copy finalization patch, exact HTTPS site-origin record, site deployment, and promotion remain separate final user approvals.
- [ ] Clean A contains the final manual records and all three reviewed workflow blobs; exact-A CI passed before E was collected.
- [ ] Final external E was created once at mode 0600, and B is A's direct single-parent child whose only change adds the unchanged E bytes at the fixed path as `100644`.
- [ ] The tag is annotated and targets A; its direct object SHA, peeled commit, and exact E-digest message are recorded. The object was created locally before B, was not pushed then, and did not move.
- [ ] B reached `master` without a merge commit; exact-B CI and the A→B semantic/history recheck passed before a separate tag-push authorization allowed the first push of the already recorded object.
- [ ] After the exact draft exists, both manual records are replaced in a reviewed docs-only master commit with new `pre-publication` phase/tag-object/peeled-commit/Release-ID challenges, canonical UTC observations no older than 24 hours, and two new source-artifact digests distinct from each other and both final-pre-tag baselines; exact-commit CI passes.
- [ ] The exclusive single-writer freeze covers master/tag/Release/assets, rulesets, both environments and bypass/reviewer/deployment settings, workflow state, Actions permissions, secret/variable names, immutable/security/labels/metadata, actor roles, and token configuration from before the two-pass read through the PATCH and post-read.
- [ ] The fresh two-pass `pre-publication` controls manifest binds the direct tag object, peeled tag commit and Release ID, all three active workflow blobs/routes, both environment deployment/reviewer records, and the two current manual evidence digests.
- [ ] Before the final remote-controls snapshot, the reviewed pre-approval master already contains the unchanged candidate inventory, predecessor lineage, three external-beta reports, and external-beta set.
- [ ] The closed-schema `publication-approval.json` follows [PUBLICATION-APPROVAL.md](PUBLICATION-APPROVAL.md), binds the actual release manifest, final-DMG provenance bundle, candidate inventory, predecessor lineage, beta set, ordered report bytes, Sonoma lifecycle report, and pre-publication controls manifest, and is added with that controls manifest in one reviewed direct-successor commit that changes only those two allowlisted evidence paths, remains inside its maximum 24-hour approval window, and passes the exact approval commit's master-push `Verify macOS app` and `Verify public site and release assets` CI jobs.
- [ ] Every timestamp is canonical UTC and the records satisfy `final manuals observedAt ≤ final E collectedAt ≤ pre manuals observedAt ≤ pre manifest collectedAt ≤ approval approvedAt`.
- [ ] The publication workflow, `release-publication` protection/actors, administrator-bypass evidence, and exact fine-grained `RELEASE_ADMIN_READ_TOKEN` contract are bound without exposing a credential value: owner `GGULBAE`, repository selection only `GGULBAE/desk-setup-switcher`, unexpired, no account/organization permissions, and exactly Actions/Administration/Attestations/Contents/Metadata read-only.
- [ ] A later run refuses an already-public Release. Same-process recovery is limited to the originating PATCH's ambiguous response. `HUP`, `INT`, `QUIT`, `TERM`, workflow cancellation, runner/host loss, unavailable or incomplete logs, and any public or post-process ambiguous state are incident-only.
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
