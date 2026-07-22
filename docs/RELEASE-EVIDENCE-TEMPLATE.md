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

The fixed lineage has two separately approved freezes. First establish the
clean `v0.0.9`/build-1 commit, run `predecessor-pre-tag` while refs/Releases are
empty, bind the resulting external evidence **E0** in one annotated predecessor
tag, and add only unchanged E0 in the required direct-child evidence commit.
After exact CI/history verification and a separate tag-push authorization,
retain the attempt-1 predecessor origin; never create a Release for it.

Next establish the descendant `v0.1.0`/build-2 commit with identical
`.github/workflows` and `scripts/release` trees. Run `final-pre-tag` while the
remote contains exactly annotated `v0.0.9` and zero Releases. Bind the resulting
external evidence **E1** in one annotated final tag and add only unchanged E1
in its required direct-child evidence commit. After exact CI/history
verification and a separate tag-push authorization, retain the distinct
attempt-1 final origin and prepare only its draft. External outputs require an
absent path outside the repository under an owner-owned mode-0700 directory and
are created mode 0600. A verifier configures, pushes, tags, dispatches, and
approves nothing.

- [ ] The predecessor is exactly annotated `v0.0.9`, app version `0.0.9`, build 1; the final candidate is exactly annotated `v0.1.0`, app version `0.1.0`, build 2.
- [ ] Both commits and submodules/dependencies are fixed, each checkout is complete and non-shallow, and each worktree is clean.
- [ ] `make verify`, `make audit-public-release`, and `git diff --check` pass on both exact tagged commits.
- [ ] Remote CI passes the required checks for both exact commits and both add-only evidence commits.
- [ ] The planned initial target remains Apple Silicon with a macOS 14.0 deployment target; no Intel or unverified Sonoma runtime claim is present.
- [ ] Release entitlements are reviewed, minimal, recorded below, and omit `com.apple.security.get-task-allow`.

| Evidence | Value or link |
| --- | --- |
| Toolchain: macOS/Xcode/Swift/SDK | `<not recorded>` |
| Verification run and counts | `<not recorded>` |
| Remote CI run | `<not recorded>` |
| Release entitlement manifest/hash | `<not recorded>` |
| Supported architecture/deployment target evidence | `<not recorded>` |

## Two protected candidate origins

Each app is built once in its own attempt-1 origin. Signing, packaging,
notarization, and stapling may change signatures and DMG bytes but must not
rebuild or change that app. A rebuild, resource change, entitlement change,
executable change, or build-number change creates a new identity and invalidates
the fixed predecessor-to-final path and every downstream beta report.

| Identity | Recorded value |
| --- | --- |
| Predecessor tag/commit and direct tag-object SHA | `<not recorded>` |
| Predecessor origin run/artifact ID/archive SHA-256 | `<not recorded>` |
| Predecessor release manifest/final DMG/provenance bundle SHA-256 | `<not recorded>` |
| Predecessor signed executable and architecture-labelled CodeDirectory hashes | `<not recorded>` |
| Final tag/commit and direct tag-object SHA | `<not recorded>` |
| Final origin run/artifact ID/archive SHA-256 | `<not recorded>` |
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

- [ ] Both apps and DMGs pass strict `codesign` verification.
- [ ] Both notary results were parsed as `Accepted`; command exit alone was not used as proof.
- [ ] Both final DMGs pass stapler validation and Gatekeeper assessment.
- [ ] Each app mounted from its final DMG passes Gatekeeper assessment and matches that origin's signed executable, architecture-labelled CodeDirectory hashes, designated requirement, entitlements, and resource manifest.
- [ ] No rebuild or app-bundle change occurred within either recorded origin.

## Protected remote controls and draft

| Control | Evidence link or read-only result |
| --- | --- |
| Default-branch protection and required CI | `<not recorded>` |
| v3 `predecessor-pre-tag`, `final-pre-tag`, and `pre-publication` outputs; exact commits; signed-candidate, CI, publication, and disabled-legacy workflow blobs; one pinned CI run/check-suite ID; both required check-run IDs; and both required job IDs | `<not recorded>` |
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
| Protected predecessor `build-candidate` origin run/attempt and immutable artifact ID/archive SHA-256 | `<not recorded; v0.0.9/build 1, attempt 1, never rerun>` |
| Protected final `build-candidate` origin run/attempt and immutable artifact ID/archive SHA-256 | `<not recorded; v0.1.0/build 2, attempt 1, never rerun>` |
| Separate `prepare-draft` verification run/attempt | `<not recorded; distinguish from candidate origin>` |
| Protected draft Release URL/ID | `<not recorded>` |

- [ ] A read-only query proves the effective remote workflow cannot publish an unsigned artifact or bypass approval.
- [ ] Each of the three v3 phases uses fresh protected screenshot/review-note bundles with visible phase/UTC challenge, false administrator bypass, distinct per-phase source SHA-256 values, exact policy operator, and no committed raw screenshot or token; each two-pass API verifier passes with zero drift and reports `manual_gates=2`.
- [ ] E0 came from `verify-remote-controls-predecessor-pre-tag`, E1 from `verify-remote-controls-final-pre-tag`, and the final manifest from `verify-remote-controls-pre-publication`; direct `remote_controls_policy.rb` output is offline component evidence and cannot replace any gate.
- [ ] The release manifest records `runner-environment=github-hosted`; each signing/notarization secret had one direct-exec consumer and was absent from unrelated child environments. The distinct admin-read token appeared in exactly six bounded workflow secret references, and the publication helper installed it only through five tracked, timeout-bounded GitHub read/download launcher call sites.
- [ ] The manifest contains `signedAppCompatibility` and `mountedAppCompatibility` records bound to the exact executable SHA-256. Both prove exactly `arm64,x86_64`, both slices report the repository-declared macOS minimum in `LC_BUILD_VERSION`, and the two records are identical.
- [ ] Normal completion and one catchable signing/notarization-cancellation probe confirm no decoded release credential or tracked notarization child remains. Do not claim shell cleanup for `SIGKILL` or host loss, and do not treat cleanup evidence as publication retry authorization.
- [ ] Both immutable exact-nine-asset workflow artifacts were finalized and their distinct IDs/archive digests and attempt-1 origins are recorded; neither origin build was rerun and the predecessor never created a Release.
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
| Exact predecessor app is copied with Finder to `/Applications/Desk Setup Switcher.app`, its DMG is ejected, and installed bundle/version/build/executable/bundle-manifest identities match its release manifest | `<not recorded>` | [ ] |
| Exact final app replaces that same path from its mounted DMG, its DMG is ejected, and installed identities match the final release manifest | `<not recorded>` | [ ] |
| Clean first launch uses only the exact `/Applications` copy and passes the menu-bar-only lifecycle | `<not recorded>` | [ ] |
| Launch at login is off by default; any optional opt-in is explicit | `<not recorded>` | [ ] |
| Capture → Edit → Review explanation works without applying a setting | `<not recorded>` | [ ] |
| Exact browser-downloaded `v0.0.9` build-1 predecessor passes quarantine/checksum/Gatekeeper/provenance checks and upgrades to exact `v0.1.0` build 2 while preserving schema-1 profiles, settings, selection, backups, and consent boundary | `<not recorded>` | [ ] |
| Synthetic schema 0→1 migration and last-known-good creation | `<not recorded>` | [ ] |
| Synthetic primary corruption recovers the last-known-good backup and quarantines safely | `<not recorded>` | [ ] |
| Import replacement and exclusive/no-overwrite export | `<not recorded>` | [ ] |
| Diagnostics browse, refresh, clear, and redaction boundary | `<not recorded>` | [ ] |
| Uninstall after disabling login item | `<not recorded>` | [ ] |
| Optional app-owned data/preferences removal, with external exports preserved | `<not recorded>` | [ ] |

## External beta and release blockers

Every report must follow [the external beta template](EXTERNAL-BETA-REPORT-TEMPLATE.md), use report schema v3, use the same final DMG SHA-256 and final-DMG provenance attestation, separately acquire the same exact predecessor DMG with real quarantine, install both origins to the exact `/Applications` path, eject before launch, bind both installed identities to their release manifests, and pass the fixed build-1-to-build-2 upgrade. Reports run on Apple Silicon within the planned macOS 14+ matrix and avoid live system-setting mutation unless separately authorized. At least one accepted report must run the full lifecycle on macOS 14 Sonoma. The actual-byte inventory, lineage, three reports, and independence-review set must validate against both restored origins and the v3 boundary; Markdown alone is not evidence.

| Report | Tester record | macOS / coverage role | Final DMG SHA matches | DMG provenance matches | Mandatory lifecycle passes | Open P0/P1 |
| --- | --- | --- | --- | --- | --- | --- |
| Beta 1 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 2 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |
| Beta 3 | `<not recorded>` | `<not recorded>` | [ ] | [ ] | [ ] | `<not recorded>` |

- [ ] At least one accepted report records Apple Silicon/macOS 14.x Sonoma and passes every mandatory exact-candidate lifecycle row.
- [ ] `candidate-inventory.json` v1 records exactly the retained protected-beta `v0.0.9`/build-1 origin below current `v0.1.0`/build 2, requires predecessor completion before the current manifest, and carries the protected completeness-review receipt digest.
- [ ] `predecessor-lineage.json` v3 binds actual inventory, predecessor manifest/DMG/provenance, E1 boundary, predecessor tag object, and E0 digest; every report records a passed mandatory upgrade.
- [ ] Each external-beta v3 report records separate predecessor and final installation evidence for exact `/Applications/Desk Setup Switcher.app`; both installed identities match their restored release manifests and neither launch comes from a mounted DMG.
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
- [ ] Protected commit P, external E0, annotated `v0.0.9`, and direct-child E0 commit satisfy the exact add-only history and digest-message contract before the separately authorized predecessor tag push/build.
- [ ] Final commit F, external E1, annotated `v0.1.0`, and direct-child E1 commit satisfy the exact add-only history and digest-message contract before the separately authorized final tag push/build; critical workflow/script trees match P.
- [ ] After the exact draft exists, both manual records are replaced in a reviewed docs-only master commit with new `pre-publication` phase/tag-object/peeled-commit/Release-ID challenges, canonical UTC observations no older than 24 hours, and two new source-artifact digests distinct from each other and both final-pre-tag baselines; exact-commit CI passes.
- [ ] The exclusive single-writer freeze covers master/tag/Release/assets, rulesets, both environments and bypass/reviewer/deployment settings, workflow state, Actions permissions, secret/variable names, immutable/security/labels/metadata, actor roles, and token configuration from before the two-pass read through the PATCH and post-read.
- [ ] The fresh v3 `pre-publication` manifest binds both direct tag objects and peeled commits, E0 and E1 digests, the final Release ID, all four workflow identities/routes, both environment deployment/reviewer records, and the two current manual evidence digests.
- [ ] Before the final remote-controls snapshot, the reviewed pre-approval master already contains the unchanged candidate inventory, predecessor lineage, three external-beta reports, and external-beta set.
- [ ] The closed-schema `publication-approval.json` follows [PUBLICATION-APPROVAL.md](PUBLICATION-APPROVAL.md), binds the actual release manifest, final-DMG provenance bundle, candidate inventory, predecessor lineage, beta set, ordered report bytes, Sonoma lifecycle report, and pre-publication controls manifest, and is added with that controls manifest in one reviewed direct-successor commit that changes only those two allowlisted evidence paths, remains inside its maximum 24-hour approval window, and passes the exact approval commit's master-push `Verify macOS app` and `Verify public site and release assets` CI jobs.
- [ ] Every timestamp is canonical UTC and ordered across predecessor-pre-tag collection, final-pre-tag collection, current pre-publication observations/collection, and approval.
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
