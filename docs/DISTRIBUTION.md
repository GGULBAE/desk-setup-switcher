# Distribution

Last updated: 2026-07-22

Desk Setup Switcher has no public release. The repository is intentionally staged at `0.0.9`/build 1 so it can build and inspect the protected predecessor as an ad-hoc-signed development DMG; that artifact is not an end-user distribution. The official `v0.1.0`/build-2 public beta is produced only after the predecessor is retained and requires Developer ID signing, hardened runtime, secure timestamps, notarization, stapling, Gatekeeper verification, protected approval, and clean-download evidence before publication.

## Distribution classes

| Class | Purpose | May be public/canonical? |
| --- | --- | --- |
| Local or CI ad-hoc DMG | Contributor testing, deterministic package inspection, and historical evidence | No |
| Ad-hoc workflow artifact or unsigned draft | Contributor inspection only; never external-beta or release evidence | No |
| Developer ID + notarized release candidate | Clean-install beta testing after all trust checks pass | Protected workflow artifact and protected draft only; never a canonical download |
| Approved `v0.1.0` GitHub Release | Canonical public-beta download with checksum, provenance, SBOM, and release evidence | Yes |
| Homebrew cask | Convenience installation after the canonical notarized release is proven | Only after the GitHub Release; own tap first |

An ad-hoc signature is never promoted by changing its description. A public artifact must be built through the separate identity-signed path and must pass every public gate below.

## Current development baseline

The current `v0.0.9`/build-1 source's 2026-07-22 no-Developer-ID path passed 5,298 deterministic checks/assertions: 516 app checks (192 XCTest cases, 323 default Swift Testing cases across 39 suites, and one isolated native `NSPopover` case in a 40th Swift Testing suite) plus 4,782 release-tooling assertions (374 base release-policy, 8 Mach-O compatibility-verifier, 659 remote-controls v1 policy/normalizer, 210 remote-controls v2 lifecycle-policy, 86 remote-controls v3 lifecycle-policy, 71 remote-controls v2 collector, 17 remote-controls v3 collector, 407 publication-approval policy, 1,386 external-beta/inventory/lineage/template policy, 132 collector-wrapper mock, 19 release-evidence history, 57 draft-reconciler mock, 261 artifact-restoration mock, 557 approved-publication mock, 306 legacy-workflow-containment mock, and 232 shell/workflow guard assertions). Universal Debug/Release, Analyze, project-generation verification, DMG creation, SHA-256 validation, mounted metadata/resources, exact `arm64 x86_64` slices, per-slice macOS 14.0 `LC_BUILD_VERSION`, and ad-hoc signature classification passed. The 39-assertion public-release audit fixture suite and complete-history/current-asset production scan also passed on 2026-07-22 after the current source and regenerated-media commits. The release-tooling evidence is simulated and structural, not a candidate-history review, external beta result, credentialed signing, notarization, protected-remote, or publication result. The package was not installed, launched, uploaded, or published.

- Current development-only DMG: `artifacts/Desk-Setup-Switcher-0.0.9-unsigned.dmg`, SHA-256 `8f37391c73432e0e1bdfb54418c1876790d3776c198c68d7e79ce5ba9d006a2a`
- Authoritative current record: [Completion criteria and evidence ledger](COMPLETION-CRITERIA.md)
- Historical 496-check baseline and DMG SHA-256 `961f4044996c0f5fc0b4e8e782355da4d620c553e4c1891918d19323f6d67eac`: [Open-source release baseline audit](OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md)

This hash is local development evidence only. It must not appear as the checksum of a signed public candidate.

## Historical P2 development baseline

The P2 baseline's no-Developer-ID path passed 461 checks: 144 XCTest cases, 316 Swift Testing cases across 39 suites, and one isolated native `NSPopover` regression. Universal Debug/Release, Analyze, DMG creation, SHA-256 validation, mounted metadata/resources, `arm64 x86_64`, and ad-hoc signature classification passed.

- P2 development DMG SHA-256: `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`
- Reinstalled P2 ad-hoc executable SHA-256: `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719`
- Authoritative records: [P2 audit](P2-UI-REFINEMENT-AUDIT-2026-07-17.md) and [P2 evidence index](evidence/p2-ui-refinement-2026-07-17/README.md)

Those hashes identify a historical development baseline, not the current changing worktree and not a release candidate. They must not be copied into `v0.1.0` release notes.

GitHub Actions run `29154880831` historically exposed a Swift 6.1 actor-isolation failure. Repair commit `4e45328` and [run `29155207923`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29155207923) passed the then-current `make verify` and unsigned artifact upload. No release workflow, Developer ID signing, notarization, stapling, or downloaded-quarantine install has passed.

## Development-only ad-hoc package

Contributors can run:

```sh
make verify
make audit-public-release
```

The packaging portion creates:

- `artifacts/Desk-Setup-Switcher-0.0.9-unsigned.dmg`
- `artifacts/Desk-Setup-Switcher-0.0.9-unsigned.dmg.sha256`

`make package` builds the universal Release app with automatic signing disabled and applies this ad-hoc signature:

```text
Signature=adhoc
Authority=(none)
```

`make verify-package` recomputes the checksum, mounts the DMG read-only, checks the app and `/Applications` link, confirms `arm64 x86_64`, validates bundle metadata and English/Korean resources, and requires a structurally valid ad-hoc signature with no identity authority. `make audit-public-release` scans complete Git history and image metadata for high-confidence credential and personal-path patterns while suppressing matched values.

These checks provide development integrity evidence only. They do not authenticate the publisher, establish an Apple trust chain, enable hardened runtime, notarize or staple the artifact, or prove the downloaded Gatekeeper path. Local and CI DMGs are not byte-for-byte reproducible, so each artifact requires its own checksum.

### Contributor installation only

If a contributor explicitly chooses to install an ad-hoc build, verify its locally supplied checksum first:

```sh
shasum -a 256 -c Desk-Setup-Switcher-0.0.9-unsigned.dmg.sha256
```

macOS may require an explicit **Open Anyway** decision for this development artifact. Never disable Gatekeeper globally or remove quarantine recursively. End-user documentation, the demo site, and promotional material must not link to this artifact or instruct ordinary users to bypass Gatekeeper.

## Proposed local workflow and effective remote path

The local workspace's proposed CI workflow uses a complete checkout, runs `make verify` and `make audit-public-release`, and uploads the ad-hoc DMG/checksum for 14 days. It does not receive signing or notarization secrets.

The local workspace now proposes one signed-candidate workflow with three
isolated manual dispatches and two operation types:

1. `build-candidate` runs once for annotated `v0.0.9`/build 1 and once for
   annotated `v0.1.0`/build 2. Each dispatch runs only through
   `workflow_dispatch` on its existing tag ref and requires the exact expected
   commit plus the tag-specific typed confirmation; a no-permission guard
   rejects mixed phase inputs before a protected job starts.
2. Both build dispatches reference the protected environment named
   `release-candidate` and receive signing/notarization values. The separate
   `prepare-draft` operation receives no signing secret and is valid only for
   `v0.1.0`.
3. Each attempt-1 build repeats preflight, `make verify`, and the public-history
   audit from a complete tag checkout on a GitHub-hosted runner, then builds
   once, signs, notarizes, staples, assesses, checksums, and records that
   candidate.
4. Each origin creates an SBOM plus separate DMG-provenance, DMG-SBOM, and
   release-manifest-provenance attestations, then retains its exact nine assets
   in one immutable artifact and records its distinct run ID, artifact ID, and
   archive SHA-256. The `v0.0.9` artifact is a protected upgrade source and must
   never create a GitHub Release.
5. A separate `prepare-draft` run names only the final build-2 origin values. It
   rejects a rerun or failed origin, verifies exact
   workflow/repository/tag/commit/job/artifact metadata, downloads the raw
   artifact ZIP by ID, fails on any digest or exact-nine-entry mismatch, and
   verifies the signed candidate plus all three attestation bundles before
   Release access.
6. Only then does it create or resume the exact `v0.1.0` draft prerelease with
   curated English/Korean notes. It rejects changed metadata or any
   extra/different asset and may add only missing byte-identical final-candidate
   assets without clobber, edit, deletion, or publication.
7. It downloads all nine draft assets again, repeats identity and bundle
   verification, retains both immutable origin artifacts for the external-beta
   path, and contains no public-release publication command.

A separate proposed manual workflow performs the final publication transition. It restores both attempt-1 artifacts, verifies each manifest/DMG/provenance identity and the final candidate's attestations, validates a closed-schema approval record from the exact remote `master` HEAD, requires both named jobs from the approval commit's exact successful master-push CI, one exact `v0.1.0` draft Release, both direct annotated-tag objects plus peeled commits, fresh phase-bound Settings records, and stable immutable-release settings. It downloads the final nine draft assets before mutation and permits only one exact-ID `draft:false`, `prerelease:true`, `make_latest:false` PATCH. It then requires the public Release to be immutable and re-downloads all nine final assets for a second verification. A later run refuses any already-public Release; only the process that sent a PATCH may resolve its own missing response by an immediate exact-state read. It cannot build, sign, notarize, create/move a tag, create a predecessor Release, edit metadata/assets, delete a Release, or deploy the site. Its full contract and current blockers are in [Public release approval](PUBLICATION-APPROVAL.md).

These workflows and release scripts are unproven local tooling. They have not run with Developer ID/notarization credentials, have not produced a signed candidate, have not published a protected Release, and have not been pushed. A draft/prerelease is not a public release, and source inspection cannot substitute for protected environment configuration or an actual accepted run.

The three dispatches enter separate protected jobs and may require separate environment approvals. Before either tag exists, local/mock structural verification plus read-only API and manual Settings readback must prove exact-ref restrictions, reviewer/self-review and administrator-bypass behavior, origin-value handoffs, build-rerun rejection, and final-draft recovery without dispatching a candidate. There is no prompt-only rehearsal path: every `build-candidate` dispatch consumes its build number and attempt-1 origin, even if credentials are absent or approval fails. The actual prompt is therefore observed and recorded only during each separately approved, credentialed, single allowed attempt-1 build; a missing or incorrect prompt stops and invalidates the fixed path. Naming an environment in YAML does not configure or prove those controls.

For either `build-candidate`, all three candidate-origin inputs remain the literal sentinel `0`. After each run succeeds, its run ID, artifact ID, and bare 64-character archive SHA-256 are retained as that tag's immutable origin identity. Only the three values from the `v0.1.0` run may be copied into a new `prepare-draft` dispatch; values must not be guessed, mixed with the predecessor, or taken from a different run. The restoration verifier requires the REST digest `sha256:<candidate_artifact_sha256>` and independently hashes each downloaded ZIP to the same bare digest before extraction.

Only attempt 1 of either `build-candidate` run may consume signing/notarization credentials or build that candidate. **Never rerun either origin run:** GitHub's full-rerun behavior removes its existing artifacts before jobs start, so the no-permission guard rejects every later build attempt and a lost origin invalidates the fixed release path. Draft preparation is a separate run bound to the final origin run ID, artifact ID, and archive digest; rerunning the draft run does not own or replace either origin artifact. If either required origin was rerun, did not finish successfully, is unavailable, or fails metadata/content verification, publication stops before mutation. An existing final draft is resumable only when its tag, title, full notes, draft/prerelease state, and every already-present asset exactly match the retained build-2 candidate. Missing assets may be appended, but no existing asset is replaced and no Release is edited, deleted, or published. Evidence records the draft run/attempt separately while preserving both original build runs.

The release scripts fail closed on self-hosted runners. Each signing/notarization secret is scoped to its one consuming workflow step, which directly replaces the runner shell with `/bin/bash`; the script copies the value into a non-exported variable and unsets the original before `source`, `dirname`, or any other child process can run. The distinct `RELEASE_ADMIN_READ_TOKEN` appears in exactly six bounded read-only workflow secret references: full-SHA-pinned checkout, combined two-origin restoration, final-candidate attestation verification, predecessor tagged-source verification, the publication helper, and post-publication final-attestation verification. The helper itself installs that token only through five tracked, timeout-bounded GitHub read/download launcher call sites; the ordinary write token is installed only for the one exact-ID PATCH. The certificate, ephemeral Keychain, and notary key use private randomized paths below `RUNNER_TEMP`; only their non-secret path names cross steps through GitHub's `GITHUB_ENV` file. The decoded certificate is deleted immediately after import, the Keychain as soon as app and DMG signing finish, and the notary key immediately after the accepted submission log is fetched, with absence checked after every normal deletion. Catchable signing/notarization cleanup targets tracked process groups, grants a short `TERM` window, then escalates to `KILL` before status-preserving cleanup; that cleanup guarantee does not make an interrupted publication retry-safe. Any publication-side `HUP`, `INT`, `QUIT`, `TERM`, workflow cancellation, runner/host loss, or unavailable/incomplete log is incident-only. `SIGKILL` delivered to the runner shell itself, host loss, and power loss cannot be handled by a shell trap and therefore retain the GitHub-hosted ephemeral runner and `RUNNER_TEMP` teardown as the last secret-cleanup boundary. Apple's `security import` still requires the certificate passphrase as a quoted `-P` process argument for that brief isolated command; it is never logged or inherited through the child environment.

After certificate import, the ephemeral Keychain must expose exactly one valid codesigning identity in total, and that identity must exactly match the reviewed Developer ID Application label. An extra valid identity, a missing match, or a malformed/inconsistent `security find-identity` inventory fails closed before signing and triggers credential cleanup; the deterministic tests use synthetic identities only.

Strict duplicate-key-free JSON validation emits the normalized submission ID from the same verified in-memory snapshot rather than reopening the raw result. JSON and text sanitization replace the longest, most-specific repository/home/runner path first, then the sanitized result and log are semantically rebound to the submission, archive, and hashes. The always-cleanup path is idempotent, never follows a signing-path symlink, and refuses malformed, escaped, or unexpected signing paths. Deterministic mock lifecycle tests exercise successful and failed import, `GITHUB_ENV` handoff, idempotent follow-up cleanup, symlink refusal, secret-environment isolation, and prompt process-group cleanup even when the child ignores `TERM`; this remains simulated evidence, not a credentialed signing/notarization run.

The effective remote workflow on `origin/master` is older and unsafe for a release tag. A read-only inspection on 2026-07-18, authenticated and repeated on 2026-07-20, 2026-07-21, and 2026-07-22, found that it triggers on `v*`, receives `contents: write`, builds an unsigned DMG, and calls `gh release create` without `--draft`, `--prerelease`, or an environment. The current local protection changes have not been pushed. Therefore **no `v*` tag may be pushed** until the safe workflow is merged, remote protections are configured, and a read-only check proves that the unsafe path is no longer effective.

At the 2026-07-22 13:48 KST GET-only observation, remote `master` was `1489b7fcb41ffa7e55a43ed65e6befc538838140`; the audited local release-control source `de4f805cfadf5fdfd1266d07286d27192794ca33` was its descendant, 39 commits ahead. Remote workflows were only CI plus active historical Release workflow `311269012`. `master` was unprotected (`protected:false`, branch protection 404), with zero rulesets, environments, repository Actions secret/variable names, `v*` tags, Releases, and Release-workflow runs. Immutable Releases, private vulnerability reporting, and full-SHA pinning were disabled; all Actions were allowed; the Homepage, topics, Pages site, and `needs-triage` label were absent; Discussions was disabled; and the description still advertised mouse and keyboard. The repository was public/MIT with Issues, a read-only default workflow token, secret scanning, push protection, Dependabot security updates, and successful existing remote-master CI.

Local containment tooling is prepared for GitHub CLI 2.95-compatible paginated GETs. With `GH_TOKEN` present, `make plan-legacy-workflow-containment EXPECTED_MASTER_SHA=<exact remote master> CONTAINMENT_PLAN_RECEIPT=/absolute/private/plan.json` performs only two complete GET-only observations and creates one owner-only mode-0600 receipt outside the repository under an owner-mode-0700 directory. It binds the exact repository/actor/admin identity, `master`, workflow ID/name/path/state, unsafe workflow blob, empty `v*` tag/Release boundary, completed workflow-run set, local tool blobs, and paginated observation digests. A receipt is private planning evidence only; it does not disable the workflow or authorize the apply step.

On 2026-07-22 that planner created private, uncommitted `legacy-workflow-containment-plan-de4f805-20260722.json` under a mode-0700 parent as a mode-0600 file. It bound exact local HEAD `de4f805cfadf5fdfd1266d07286d27192794ca33` and four tool blobs, recorded workflow `311269012` as active with zero tags and Releases, and had plan digest `bb53444e29871dd077d975128f0d41299d484d694429939a5e9f7daa11e0d4e6`; a separate `validate-plan` invocation using the same checked-in validator accepted it. This is planning evidence only: no apply, PUT, push, tag operation, dispatch, or other remote mutation occurred. Apply compares the current clean checkout HEAD and tool blobs with the receipt, so this receipt is accepted only from a clean checkout of `de4f805cfadf5fdfd1266d07286d27192794ca33`; any later HEAD must create and review a new GET-only plan.

The apply target is intentionally separate. Only after reviewing a receipt whose bound HEAD and tool blobs match the unchanged clean apply checkout, and obtaining explicit approval, may the operator set `DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1`, type `DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION="DISABLE WORKFLOW 311269012 AT <exact remote master>"`, and run `make apply-legacy-workflow-containment` with the same expected SHA, plan path/digest, and a new absent result path. Apply validates the receipt and local tools, repeats two full pre-observations, sends at most one fixed bodyless `PUT /repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable` only if still active, requires an exact 204/empty response, and repeats two post-observations proving that only `active`→`disabled_manually` changed. An already manually disabled workflow produces a zero-PUT result. Any uncertainty after the PUT is exit 75 with no success receipt and is incident-only: preserve state, read it back separately, and never retry automatically or enable the workflow. The helper cannot enable, dispatch, cancel, tag, create/edit a Release, push, or merge.

Containment threat boundary: this helper assumes a trusted local account, repository checkout, and local Git, Ruby, and `gh` toolchain. Its no-follow descriptor reads, Git-blob checks, bounded streaming hash/HMAC, identity checks, root-owned empty `gh` configuration, minimal child environment, and signal handling defend capture-path precreation, replacement, truncation, and ambiguous-result races during an authorized invocation. They are not a sandbox against a malicious same-UID process, hostile token-holding caller, compromised checkout/runtime, or substituted toolchain. The internal operation/plan authorization string is a fail-closed accidental-misuse guardrail, not authentication of a hostile caller.

Do not push either `v0.0.9` or `v0.1.0` until the release-only signed path is merged and the `release-candidate` environment is actually protected for both exact tags. Referencing an environment in workflow YAML does not configure protection by itself. Read-only GitHub API checks on 2026-07-18, 2026-07-20, 2026-07-21, and 2026-07-22 found zero configured environments and no protection on `master`.

The detailed [remote release controls audit](REMOTE-RELEASE-CONTROLS-AUDIT-2026-07-18.md) additionally records zero branch/tag rulesets, disabled immutable releases and private vulnerability reporting, empty repository secret/variable name lists, the missing protected environment, the pending sole-maintainer reviewer-policy decision, stale repository metadata, and the exact containment → feature-branch → PR → read-back sequence. It inspected no credential value. That audit authorizes no remote mutation; it exists so approval can name a bounded operation and rollback path.

Remote controls use three explicit read-only gates. `make verify-remote-controls`
is the compatibility alias for `verify-remote-controls-predecessor-pre-tag`;
`verify-remote-controls-final-pre-tag` additionally requires the exact
predecessor commit and annotated tag-object SHA; and
`verify-remote-controls-pre-publication` additionally requires the final commit,
annotated final tag-object SHA, and exact draft Release ID. Each external output
destination must be absent, outside the repository, and inside an owner-owned
mode-0700 directory; the gate atomically creates one mode-0600 normalized record
without overwriting an existing path. These commands are intentionally excluded
from ordinary `make verify` because credentials and network state are not
deterministic test inputs.

The checked-in v3 lifecycle policy is fail-closed and currently
`configured:false`, so an operational command stops before resolving `gh` or
making a GitHub request. Its closed schema binds four workflow identities and
blobs: signed candidate, CI, publication, and the disabled fail-only legacy
tombstone. It also binds the complete workflow inventory; the exact **Verify
macOS app** and **Verify public site and release assets** check runs/jobs from
one successful master-push check suite; both protected environments and their
tag/reviewer/self-review/deployment records; operator, reviewer, and publisher
numeric identities; credential-name scopes and repository shadow exclusions;
and the exact path/control/schema contract for two manual records. Each phase
manifest binds its current record-byte digests.

The phase boundaries are exact: `predecessor-pre-tag` requires zero `v*` refs
and zero Releases; `final-pre-tag` requires only the annotated `v0.0.9` ref with
its exact object and peeled commit, the earlier evidence digest, and zero
Releases; `pre-publication` requires both annotated tags, both earlier evidence
digests, and exactly one `v0.1.0` draft prerelease. Only secret/variable names
are emitted, persisted, normalized, compared, or recorded; no credential value
is inspected or retained. GitHub's REST response still does not prove either
environment's administrator-bypass setting or the admin-read token's
least-privilege configuration, so those facts remain exactly two protected
Settings/manual evidence items. Calling
`scripts/release/remote_controls_policy.rb` directly with a normalized fixture
exercises only the offline policy component; it is not a live remote gate and
must not be recorded as one.

The phase order is strict. First establish the protected `v0.0.9` build-1
source commit with fresh `predecessor-pre-tag` manual records and exact-commit
CI. Run the zero-tag/zero-Release verifier and preserve its external mode-0600
output. Create one annotated `v0.0.9` tag object targeting that commit and
binding the evidence digest, but do not push it. Add only the unchanged evidence
bytes in the required direct-child commit, pass exact CI/history checks, obtain
a separate tag-push authorization, then push that recorded object and build the
attempt-1 predecessor origin. It remains protected evidence and never receives
a GitHub Release.

Next establish the descendant `v0.1.0` build-2 source commit while keeping
`.github/workflows` and `scripts/release` identical across the two tagged
commits. With exactly `v0.0.9` present and zero Releases, capture fresh
`final-pre-tag` manual records and run the second verifier. Its evidence must
bind the predecessor tag object and predecessor-pre-tag digest. Create one
annotated `v0.1.0` object targeting the build-2 commit and binding that second
digest; add only its unchanged evidence bytes in the required direct-child
commit. After exact CI/history checks and a separate authorization, push that
recorded object, build the distinct attempt-1 final origin, and prepare only its
draft.

After the mandatory predecessor upgrade and all final evidence, capture fresh
`pre-publication` manual records and pass exact CI. Impose the exclusive
Settings/repository single-writer freeze, run the third verifier, then add only
its manifest and the approval in one direct-successor commit and pass that
commit's CI before dispatch. All timestamps are canonical UTC and monotonic
across predecessor-pre-tag collection, final-pre-tag collection, current
pre-publication observations/collection, and approval. The two final-pre-tag
manual source artifacts and two current pre-publication source artifacts must
remain four distinct SHA-256 values. Exact JSON fields, safe value-free
templates, archive/renewal rules, and the freeze surface are in [Public release
approval](PUBLICATION-APPROVAL.md).

Configure the authoritative policy through a reviewed code change, not by copying the synthetic fixture. Populate every closed-schema field from reviewed read-only evidence: repository numeric and node identity plus approved metadata/state, both fixed release tags/builds, signed-candidate, CI, publication, and disabled-legacy workflow IDs/names/paths/blobs, both exact CI check identities, operator, reviewer, and publisher IDs/logins/types, and approval mode/count/self-review behavior. Review that diff, commit the policy together with all four workflow blobs it names, merge it through the protected `master` path, and wait for exact-commit CI. The first operational command must then run from a clean, complete, non-shallow checkout whose HEAD is the effective remote `master`, authenticated as the configured operator with repository-admin visibility, while no remote `v*` ref or GitHub Release exists. Capture its sanitized transcript before creating the local predecessor tag object; the verifier configures nothing, pushes nothing, and does not itself authorize a tag push.

Before any release tag is allowed, a repository administrator must:

- create the `release-candidate` and `release-publication` environments, restrict `release-candidate` to the exact `v0.0.9` and `v0.1.0` tags, and restrict `release-publication` to only `v0.1.0`;
- configure the real required reviewer, publisher, and self-review behavior, then separately record each environment administrator-bypass setting from the Settings UI;
- store only the exact signing/notarization credential names in that protected environment and prove the repository level does not shadow them;
- store the shared non-secret `DEVELOPER_ID_APPLICATION` and `APPLE_TEAM_ID` variables plus `RELEASE_ADMIN_READ_TOKEN` in `release-publication`; keep all signing/notarization secrets absent there. The token must be an unexpired fine-grained token owned by `GGULBAE` and restricted to `GGULBAE/desk-setup-switcher`; grant exactly Actions, Attestations, Contents, repository Administration, and GitHub's implicit Metadata read-only access, with no account/organization permission or other repository; prove that no repository-level secret shadows it, and record the review without exposing the value;
- protect `master` with the exact required CI/review rules and no standing bypass actor; emergency recovery is a separately approved ruleset change or disable;
- use one `v*` creation ruleset with only the approved release-operator User as bypass and a separate no-bypass `v*` update/deletion ruleset, so tag creation authority never becomes tag-move or tag-delete authority;
- require selected GitHub-owned Actions, full-SHA pinning, read-only default workflow tokens, and no workflow PR-review approval permission;
- enable immutable Releases and the private reporting path required by [SECURITY.md](../SECURITY.md);
- create `needs-triage`, apply the exact approved public repository metadata and disabled-Discussions state; and
- merge the anchored policy/workflows and pass exact-commit CI; keep all `v*` refs and Releases empty through `predecessor-pre-tag`, then allow only the exact predecessor ref and no Release through `final-pre-tag`.

See [GOVERNANCE.md](../GOVERNANCE.md) for current roles and approval authority. GitHub documents that environment secrets remain unavailable until required approval when that protection is configured; merely referencing an environment supplies no such guarantee.

## Required public-beta trust path

This path is mandatory for `v0.1.0`. Proposed local workflow and helper tooling now implement two protected candidate builds, separate additive-only final-draft recovery, and approval-bound exact publication from two retained attempt-1 origin artifacts, but they are unpushed, unconfigured, and unproven with release credentials or a real approval; no signed candidate exists yet. The operator must preserve `v0.0.9`/build 1 as the exact protected-beta upgrade source and `v0.1.0`/build 2 as the exact final candidate. A retry after any source, resource, entitlement, or executable change creates a new candidate identity and invalidates this fixed path.

“Same candidate” applies independently to each origin: its source commit, tag, app version, build number, signed executable bytes, architecture-labelled `arm64` and `x86_64` CodeDirectory hashes, designated requirement, entitlements, resources, and supported architecture set do not change after that build. Packaging, notarization, and stapling legitimately change DMG bytes, so each evidence record retains its pre-notarization and final post-staple DMG hashes rather than claiming those containers are byte-identical. The app mounted from each final DMG must match that origin's recorded signed app identity and resource manifest. Every tester report binds both the predecessor and final identities; the final checksum, SBOM, three final attestation bundles, draft assets, and re-downloaded public assets bind the final post-staple build-2 DMG where applicable. Any rebuild or app-bundle change creates a new build number and invalidates earlier lifecycle and beta reports.

Sections 1–4 apply independently to both protected origins. The predecessor and
final app must each be built, signed, packaged, notarized, stapled, mounted, and
verified exactly once from its own approved tag/commit. Only the handling of the
result differs: preserve the predecessor's nine assets solely in its immutable
origin artifact, while the final nine assets may proceed to the draft.

### 1. Freeze and audit both candidate origins

- For each origin, start from its clean approved commit whose app version, build number, annotated tag, changelog, support matrix, and completion ledger agree.
- Run `make verify`, `make audit-public-release`, and `git diff --check` from a complete checkout.
- Confirm the planned public-beta platform is Apple Silicon and the deployment target is macOS 14.0 unless later evidence changes that boundary. Do not claim macOS 14 runtime support until the exact-candidate Sonoma lifecycle gate below passes; do not claim Intel unless physical Intel verification has been recorded.
- Audit the minimum entitlements. Hardened-runtime exceptions require an explicit justification; `com.apple.security.get-task-allow` must not be present in the release signature.
- Confirm the Apple Developer Program team, Developer ID Application certificate, and notarization credential are available without exporting or logging secrets.

### 2. Build each origin once and sign it for distribution

Build each exact origin once, in its own attempt-1 protected dispatch. Sign nested code from the inside out if any is introduced, then sign that origin's app with a **Developer ID Application** identity, hardened runtime, and secure timestamp. Illustrative verification commands are:

```sh
codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
  --options runtime \
  --timestamp \
  "Desk Setup Switcher.app"

codesign --verify --all-architectures --deep --strict --verbose=2 "Desk Setup Switcher.app"
codesign --display --architecture arm64 --verbose=4 "Desk Setup Switcher.app"
codesign --display --architecture x86_64 --verbose=4 "Desk Setup Switcher.app"
codesign --display --entitlements - "Desk Setup Switcher.app"
```

If the audited app needs entitlements, the implemented script must add `--entitlements` with the reviewed release plist; it must not reuse debug entitlements implicitly. The release script must supply `--options runtime` and `--timestamp` when signing. It must inspect the authority chain and fail if the identity, Team ID, hardened-runtime flag, secure timestamp, or reviewed entitlement set differs from policy. Ad-hoc signing, Apple Development, and Mac App Distribution identities are not substitutes for Developer ID Application.

Package each exact signed app without rebuilding it. Sign that origin's final DMG with the reviewed Developer ID identity and a secure timestamp, then verify that the mounted app preserves the signed executable hash, both architecture-labelled CodeDirectory hashes, designated requirement, entitlements, and recorded resource manifest of the app that entered packaging. The commands below show the final filename; the predecessor run uses `Desk-Setup-Switcher-0.0.9.dmg` under the same checks:

```sh
codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  "Desk-Setup-Switcher-0.1.0.dmg"
codesign --verify --strict --verbose=2 "Desk-Setup-Switcher-0.1.0.dmg"
```

### 3. Notarize, staple, and assess each origin

Use `notarytool`, not the retired `altool`, with credentials stored in a protected Keychain profile or protected CI secret. The operator flow is:

```sh
xcrun notarytool submit "Desk-Setup-Switcher-0.1.0.dmg" \
  --keychain-profile "NOTARY_PROFILE" \
  --wait \
  --output-format json > notary-result.json

xcrun notarytool log "SUBMISSION_ID" notary-log.json \
  --keychain-profile "NOTARY_PROFILE"

xcrun stapler staple "Desk-Setup-Switcher-0.1.0.dmg"
xcrun stapler validate "Desk-Setup-Switcher-0.1.0.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "Desk-Setup-Switcher-0.1.0.dmg"
```

The implementation must parse each origin's submission result and require `Accepted`; command exit alone is insufficient. Preserve each submission ID and redacted notary log as release evidence. Staple and validate each final DMG, mount it read-only, and assess its contained app separately with `spctl --assess --type execute --verbose=4`. Any modification after signing or notarization invalidates that origin and the fixed two-build path.

### 4. Verify both origins and attach only final release evidence

After stapling each origin, compute its final SHA-256 and verify:

- Developer ID authority, Team ID, hardened runtime, secure timestamps, and minimal entitlements;
- notarization result/log and stapler validation;
- Gatekeeper assessment of both DMG and app;
- the exact `arm64` + `x86_64` slice set and a macOS 14.0 `LC_BUILD_VERSION` minimum on each slice, rechecked both after signing and from the mounted final DMG, bound to the executable SHA-256, and independently matched to the repository policy by the candidate verifier;
- resources, localization, bundle ID, app/build versions, and login-item opt-in behavior;
- checksum file syntax and recomputation;
- an SBOM for the exact candidate;
- three separate GitHub attestation bundles: final-DMG provenance, final-DMG SPDX 2.3 SBOM, and release-manifest provenance, each bound to its exact subject; and
- tag, commit, workflow run, source tree, and artifact identity.

Each origin produces exactly nine assets: the signed/stapled DMG, checksum, SPDX JSON, release manifest, sanitized notary result, sanitized notary log, DMG provenance bundle, DMG SBOM bundle, and release-manifest provenance bundle. Preserve the predecessor set only in its immutable attempt-1 workflow artifact and never create a Release for it. Attach exactly the final origin's nine assets to the protected `v0.1.0` draft. Curated English/Korean notes are the Release body, not an asset. The local workspace contains proposed SBOM, attestation, and signed-release tooling, but it has not run with protected credentials or produced an accepted candidate; none of those outputs may be claimed yet.

Download the final draft's nine assets back through GitHub, require that no extra or missing asset exists, compare each byte-for-byte with the approved final origin, recompute hashes, verify signatures, and verify all three final attestation bundles. Separately restore and fully verify the predecessor's nine-asset origin using the predecessor tag's own code; those assets never attach to the draft. GitHub immutable releases are available to this repository and must be enabled before publication; the approval evidence must include a read-only confirmation of that setting. The final decision must then be serialized under the closed [public release approval contract](PUBLICATION-APPROVAL.md). Its v2 validator binds structure, identifiers, actual evidence bytes, actors, gates, and a maximum 24-hour window. The publication helper additionally interprets the actual candidate inventory, closed predecessor-lineage, external-beta set, and three reports against both restored release manifests and provenance bundles; arbitrary digest strings no longer satisfy those gates. No workflow may turn an unsigned artifact or an unapproved draft into a public release.

## Clean-download public-beta gate

Test the exact downloaded and quarantined candidate on a clean account or Mac without deleting or manufacturing quarantine metadata. Use [the release evidence template](RELEASE-EVIDENCE-TEMPLATE.md) for the lifecycle record and [the external beta template](EXTERNAL-BETA-REPORT-TEMPLATE.md) for each tester.

The three external testers must obtain the final stapled DMG from the protected workflow artifact produced by the approved run. They must download the artifact archive through a normal browser, extract the DMG through the normal macOS path, and record the actual `com.apple.quarantine` value on the extracted DMG before opening it. A report does not count when that attribute is absent, was manually added, or was deleted. Testers need read access to the public repository and artifact, not push, release, environment, or secret access. Each report must verify the identical final DMG SHA-256 and the final-DMG provenance attestation bound to the protected workflow run. At least one accepted report must run the complete lifecycle on Apple Silicon/macOS 14 Sonoma; deployment-target metadata alone cannot close the minimum-OS support gate. The actual-byte candidate inventory, predecessor-lineage record, three privacy-safe JSON reports, and protected independence-review set described in [the lineage contract](PREDECESSOR-LINEAGE.md) must pass `external_beta_policy.rb verify-set` against the restored candidate before approval can pass.

`external_beta_template_cli.rb` provides stdout-only, current-schema
inventory, lineage, report, and set shapes with reserved rejected placeholders.
Its isolated load closure reads no candidate/host data, writes no files, and
produces no approval or evidence digest. The separate verification policy does
not load or dispatch the generator. Operators must preview and copy a selected
shape through the protected editor workflow, replace it only with reviewed
facts, connect actual byte digests in dependency order, and obtain a separate
`verify-set` success.
Tracked rejected placeholders under `docs/evidence/releases/` fail the public
audit.

The lifecycle gate is itemized; one successful first launch cannot stand in for the other rows:

1. Verify the protected final-candidate checksum file before mounting.
2. Confirm Gatekeeper identifies the Developer ID publisher and opens the app without an **Open Anyway** workaround.
3. For both the predecessor and final candidate, copy the app with Finder from the mounted DMG to exact `/Applications/Desk Setup Switcher.app`, eject the DMG before launch, and record a sanitized transcript digest. A launch from `/Volumes`, `~/Applications`, an alias, or another path does not count.
4. Before each launch, verify the installed bundle identifier, version/build, executable SHA-256, and canonical bundle-manifest SHA-256 against that origin's release manifest. Launch only the exact `/Applications` copy.
5. Verify first launch, menu-bar-only behavior, Capture → Edit → Review & Apply explanation, permissions, and launch-at-login default-off/explicit opt-in.
6. Verify the mandatory upgrade from the exact retained protected-beta `v0.0.9` build 1 to the exact final `v0.1.0` build 2 at that same installed path. Browser-download and verify both origin artifacts, and prove that schema-1 profiles, settings, selection, backups, and the login-item consent boundary are preserved. Record both manifests, DMG/provenance hashes, origin identities, quarantine evidence, and both installation identities. There is no not-applicable variant.
7. Verify a synthetic schema-0 document migrates to schema 1, remains semantically valid, and preserves a recoverable last-known-good backup without applying a system setting.
8. With the app closed and only synthetic data present, exercise primary-file corruption and verify last-known-good backup recovery, quarantine behavior, and a clean relaunch. Do not upload raw profiles or diagnostics.
9. Verify import replacement/no-overwrite export, diagnostics browse/refresh/clear, and denial isolation with redacted or synthetic values.
10. Verify uninstall removes the exact `/Applications/Desk Setup Switcher.app` after disabling the optional login item, then separately verify optional removal of the app-owned Application Support data and preferences. Confirm exported files outside app storage are not silently deleted.
11. Record Apple Silicon and exact macOS results. Designate at least one full passing report as the macOS 14 Sonoma minimum-OS gate. Do not advertise Intel until the physical Intel matrix passes.
12. Collect at least three external clean-install beta results for the identical candidate and obtain the release-blocker sign-offs below before public approval.

### Severity and zero-blocker sign-off

- **P0 — stop/withdraw:** a credible security or privacy compromise, credential exposure, data loss, release-integrity failure, unsafe persistent system mutation, or failure that leaves the Mac without the documented recovery route. A P0 stops testing and publication immediately.
- **P1 — release blocker:** the official candidate cannot install, upgrade, launch, migrate/recover profiles, uninstall safely, or complete the supported Capture → Edit → Review flow on supported Apple Silicon/macOS without a safe documented workaround; or rollback/safety state is materially misleading. A P1 blocks publication.

The triager proposes severity from sanitized evidence. The maintainer owns the public product-severity decision; the security responder owns confidential security severity. The release approver must record both (a) a read-only query showing zero open public P0/P1 issues for the candidate and (b) a security-responder yes/no sign-off that no confidential P0/P1 release blocker remains. Do not publish private-report counts, titles, reporter identities, or details. Every P0/P1 must be closed by a new candidate or an explicitly verified non-code resolution before approval; re-labelling alone does not resolve it.

No live display, audio, or network mutation is authorized by this distribution procedure. Hardware mutation evidence requires its own explicit approval, preflight snapshot, interactive action, and rollback procedure from the [support matrix](SUPPORT-MATRIX.md). Features without that evidence remain labelled mock verified, live-read verified, experimental, or unverified.

Keyboard operation, accessibility names/values, and non-color cues remain release requirements. Full-app VoiceOver certification is not a release gate and must not be claimed.

## Homebrew sequence

GitHub Releases remains the canonical download. Do not create or advertise a cask until the Developer ID-signed, notarized, stapled public artifact has a stable GitHub Release URL and final SHA-256.

After that release:

1. Add a cask to a project-owned tap using the canonical versioned URL and exact checksum.
2. Define uninstall and `zap` behavior that accurately covers the app bundle and optional app-owned local data without deleting unrelated files.
3. Verify clean `install`, `upgrade`, `uninstall`, and `zap` on supported macOS/Apple Silicon using the downloaded notarized artifact.
4. Keep the official Homebrew Cask submission as a later milestone after the self-hosted tap and patch-release process are proven.

Homebrew must not become a runtime dependency, and the app must not gain an updater or outbound network path. `v0.1.0` publication may continue to say “Homebrew not offered”; however, the overall open-source release goal remains incomplete until the post-release own-tap `install`, `upgrade`, `uninstall`, and `zap` record passes against the canonical final SHA-256. Official Homebrew Cask submission remains a later non-goal.

## Release failure and support policy

Publication renewal is allowed only after a named normal fail-closed exit with
complete logs proves that no PATCH attempt began and every tracked process
ended normally. `HUP`, `INT`, `QUIT`, `TERM`, workflow cancellation,
runner/host loss, unavailable or incomplete logs, a public Release, or any
ambiguous PATCH outcome is incident-only: preserve state, perform read-only
review, and never automatically retry or adopt the result.

Never replace a published asset or move/reuse its tag to hide a problem. Mark the affected release as discontinued or affected, stop promotion/download links, and publish a corrected patch version through the full gate. Follow the [release incident runbook](RELEASE-INCIDENT-RUNBOOK.md), preserving the affected tag, all nine assets, hashes, and all three attestation bundles as evidence. The latest non-affected beta is the support target; the immediately preceding beta may receive critical fixes for up to 30 days when practical. The stable support window is the latest and immediately preceding stable minor lines, as defined in [Compatibility and versioning](COMPATIBILITY.md).

## Final release evidence checklist

For each public release, complete [the release evidence template](RELEASE-EVIDENCE-TEMPLATE.md) as the human-readable evidence record, then create the separately reviewed closed-schema [publication approval record](PUBLICATION-APPROVAL.md). Keep curated English/Korean notes under [`docs/releases/`](releases/); Release notes are not evidence. At minimum, record:

- tag, commit, app version, build number, clean-worktree status, and protected approval;
- Xcode, Swift, SDK, runner macOS, supported CPU, and deployment target;
- `make verify`, `make audit-public-release`, `git diff --check`, remote CI, and version/tag checks;
- exact build/sign/package lineage for both the protected `v0.0.9`/build-1 predecessor and final `v0.1.0`/build-2 candidate, with no rebuild within either origin;
- Developer ID authority/Team ID, hardened runtime, secure timestamps, and reviewed entitlements;
- notary submission ID, accepted status, redacted log, stapling, and app/DMG Gatekeeper assessments;
- mounted package resources, checksum, SBOM, the three subject-specific attestation bundles, and exact nine-asset re-download identity;
- browser-download and extracted-DMG quarantine evidence, clean first launch, login default-off, upgrade, schema migration, backup recovery, import/export, diagnostics, uninstall, and optional local-data removal as separate results;
- both annotated tag objects and peeled commits; predecessor-pre-tag, final-pre-tag, and pre-publication v3 evidence digests; both distinct attempt-1 origin run/artifact identities; an actual-byte candidate inventory and predecessor lineage; actual predecessor manifest/DMG/provenance/boundary files; three actual-byte-bound external beta reports with mandatory predecessor acquisition/upgrade; their protected independence-review set; identical final DMG/provenance identity; zero public P0/P1 issues; and confidential security-responder zero-blocker sign-off;
- capability claims matched to the support matrix, with no Intel, hardware-mutation, or VoiceOver certification overclaim;
- GitHub Release URL plus synchronized site, README, English/Korean notes, and support/security documents; and
- immutable releases enabled before publication;
- Homebrew status, explicitly “not offered” until the post-release own-tap `install`/`upgrade`/`uninstall`/`zap` record passes; and
- explicit maintainer approval for the final artifact, tag, release notes, site, and each promotional post.

Do not include personal device identifiers, real SSIDs, exact locations, IP host addresses, credentials, or unredacted diagnostics in release evidence.

## Authoritative references

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [GitHub: Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub: Variables reference](https://docs.github.com/en/actions/reference/workflows-and-actions/variables)
- [GitHub: Workflow commands and `GITHUB_ENV`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands)
- [GitHub: Using artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations)
- [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
