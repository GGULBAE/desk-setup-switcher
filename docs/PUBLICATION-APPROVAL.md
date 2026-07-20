# Public release approval contract

Desk Setup Switcher publishes `v0.1.0` only from the manual
`Publish approved signed release` workflow. That workflow does not build, sign,
notarize, create a tag, prepare a draft, or deploy the site. It can perform one
mutation only: change the already verified, exact-ID draft prerelease to a
public prerelease with `make_latest` disabled. It then re-downloads and verifies
the same nine assets.

This is a local, unproven publication design. It is not authorization to create
or publish a Release. The workflow, approval record, and remote controls have
not run on GitHub, and no real approval record exists.

## Required remote boundary

Before any release tag is pushed to GitHub, all of these conditions must be
configured and verified read-only:

- the effective workflow blobs are exactly the three reviewed files at their
  approved commits: the combined candidate/draft workflow, CI workflow, and
  publication workflow;
- `master`, the exact `v0.1.0` tag, and both `release-candidate` and
  `release-publication` environments have the reviewed protection, reviewer,
  self-review, and administrator-bypass behavior;
- the publication environment contains only the required protected values,
  including a `RELEASE_ADMIN_READ_TOKEN` secret with repository Administration
  **read-only**, Actions **read-only**, Attestations **read-only**, and Contents
  **read-only**, plus GitHub's implicit Metadata **read-only**, access in exactly
  five bounded workflow uses: the full-SHA-pinned checkout, candidate
  restoration, pre-publication attestation verification, the publication
  helper, and post-publication attestation verification. Inside the publication
  helper, the token is installed only through its five tracked, timeout-bounded
  GitHub read/download launcher call sites;
- the ordinary job token retains only `contents:write` because GitHub scopes
  permissions per job. GitHub documents that every `uses:` action in that job
  can access `github.token` even when it is not passed as an input. The sole
  accepted action boundary is the full-SHA-pinned, GitHub-owned
  `actions/checkout`; it is explicitly given the read-only PAT and uses
  `persist-credentials:false`. Shell steps expose the write token only to the
  exact publication helper, whose tracked launcher receives it outside argv
  and the launch environment, replaces the transfer stream with `/dev/null`,
  and installs it only for the single exact-ID Release PATCH process;
- immutable Releases and private vulnerability reporting are enabled; and
- no remote tag or Release exists before the approved first-release sequence
  begins.

The v2 lifecycle policy and offline normalizer now bind all three active
workflows, both required CI check runs/jobs from one successful check suite,
both environments, the operator/reviewer/publisher identities, the admin-read
secret name, repository-shadow exclusions, and the exact paths, controls, and
schema of two manual evidence records. Each phase manifest—not
the long-lived policy—binds the fresh record-byte digests. The checked-in
operational policy remains `configured:false`; no live
two-pass record exists. Until it is reviewed, configured, merged, and passed
twice—once before the tag and again after the exact draft—plus the separate
Settings evidence, the publication workflow is deliberately **not
release-ready**.

The pinned GitHub-owned `actions/checkout` commit receives the protected
read-only token with `persist-credentials:false`. That prevents the credential
from being written into the checkout's Git configuration; it does not turn an
unpinned or unreviewed action into trusted code. Any checkout SHA change is a
release-control change and must be reviewed and re-anchored.
The implicit job-token access described above is an accepted job-scoped trust
limitation; GitHub Actions does not provide step-scoped `permissions`.

## Approval record location and lifetime

The exact record path is:

```text
docs/evidence/releases/v0.1.0/publication-approval.json
```

Create it only after the immutable candidate draft, the fresh two-pass
`pre-publication` controls manifest, clean quarantined lifecycle,
three external beta reports, public and confidential zero-P0/P1 sign-offs, and
public-surface evidence are complete. The record must be one ordinary tracked
blob in a reviewed commit that descends from the release tag. At dispatch:

- that approval commit must equal the current remote `master` HEAD and be the
  single direct successor of the manifest's observed `master` commit;
- the direct-successor diff must add exactly
  `remote-controls-pre-publication.json` and `publication-approval.json`; the
  release-tag, observed-master, and approval-commit workflow/script trees must
  be identical;
- the separately supplied SHA-256 must match the descriptor-bound record bytes;
- `approvedAt` and `expiresAt` must be canonical UTC timestamps;
- the approval window must be no longer than 24 hours, still active, and have
  at least five minutes remaining both during preflight and at the final point
  immediately before the PATCH;
- every publication dispatch and any replacement dispatch must be attempt 1;
  a GitHub workflow rerun is rejected before entering the protected
  environment, and each new dispatch requires a new environment approval;
- any Release already public when a later workflow starts is incident-only and
  must never be adopted as a successful retry; and
- `approverLogin`, `publisherLogin`, numeric remote-policy actors, approval
  mode, and the protected-environment decision must agree case-insensitively by
  login and exactly by numeric ID where GitHub exposes it.

The environment approver agreement is not proved by the approval JSON or by an
`environment:` line in workflow YAML. It depends on the v2 API record for the
actual deployment policy/reviewer/self-review fields and separate read-only
Settings evidence for administrator-bypass behavior and the minimum token
scope that GitHub's environment API does not expose.

Do not merge another commit between approval and dispatch. A changed remote
`master` invalidates the approval and requires a newly reviewed record. From
immediately before the pre-publication two-pass read until the publication
PATCH and post-read finish, impose an exclusive single-writer freeze on
`master`, the tag and Release/assets, rulesets, both environments (reviewers,
self-review, deployment policy, and administrator bypass), workflow files and
active states, Actions permissions, repository/environment secret and variable
names, immutable Releases, private vulnerability reporting, labels/repository
metadata, actor roles, and the read-token configuration. The helper re-reads
`master`, the annotated tag, Release/assets, immutable Releases, actor identity,
manual blobs, and approval-commit CI; the operating freeze is the fail-closed
contract for the remaining Settings surfaces. Any observed or suspected change
ends the attempt and requires a fresh phase snapshot and approval.

## Manual Settings evidence contract

The two exact tracked paths are:

```text
docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json
docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json
```

Each is a nonempty, ordinary `100644` UTF-8 JSON blob no larger than 64 KiB,
with no duplicate or extra keys. Never commit a screenshot, token, token value,
secret value, private Settings URL, or personal path. In a protected evidence
store, capture a new screenshot-plus-review-note bundle that visibly includes
the phase challenge (`phase`, UTC observation time, and for pre-publication the
Release ID, peeled commit, and direct annotated-tag object SHA). Redact it,
review the redaction, hash the exact protected bundle bytes, and record only
that SHA-256 as `sourceArtifactSHA256`. Merely relabelling an earlier screenshot
is forbidden: the two controls and two phases must yield four distinct source
artifact digests.

The common closed shape is:

```json
{
  "schemaVersion": "desk-setup-switcher.manual-release-control-evidence/v1",
  "phase": "final-pre-tag",
  "control": "release-candidate-administrator-bypass-disabled",
  "administratorBypassEnabled": false,
  "token": null,
  "tokenPermissions": [],
  "observer": { "id": 0, "login": "<policy-operator>", "type": "User" },
  "observedAt": "<canonical-UTC-time>",
  "sourceArtifactSHA256": "<protected-bundle-sha256>",
  "redactionReviewed": true,
  "subject": { "tag": "v0.1.0" }
}
```

For `release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope`,
`tokenPermissions` must be exactly this ordered set and no other permission:

```json
["actions:read", "administration:read", "attestations:read", "contents:read", "metadata:read"]
```

Its `token` field must also be exactly:

```json
{
  "type": "fine-grained-personal-access-token",
  "resourceOwner": "GGULBAE",
  "repositorySelection": ["GGULBAE/desk-setup-switcher"],
  "accountPermissions": [],
  "organizationPermissions": [],
  "issuedAt": "<canonical-token-issuance-UTC-time>",
  "expiresAt": "<canonical-future-UTC-time>"
}
```

Create a new release-specific token as part of the protected capture ceremony.
`issuedAt` must be the canonical issuance time shown by that ceremony,
`issuedAt <= observedAt`, and capture must finish no more than 900 seconds
(15 minutes) after issuance. The actual token lifetime from `issuedAt` through
`expiresAt` must be positive and no more than exactly 30 days. A current gate
also requires at least 2,700 seconds (45 minutes) remaining at verification
time; exactly 2,700 seconds is accepted and 2,699 is rejected. Historical
`final-pre-tag` records retain the same issuance/capture and 30-day lifetime
contract but are not required to remain unexpired at the later publication.
Any additional repository, account permission, organization permission,
repository, token type, overlong lifetime, stale issuance capture, or short
current residual is rejected. Rotate the protected secret and capture new
evidence before either boundary; never record the credential value.

GitHub documents Metadata as the implicit read-only permission added to a
fine-grained Contents-read token; it is not an extra write capability. See
[GitHub's fine-grained PAT template documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#pre-filling-fine-grained-personal-access-token-details-using-url-parameters).

For each `pre-publication` record, replace `phase` and `subject` exactly:

```json
{
  "phase": "pre-publication",
  "subject": {
    "peeledCommit": "<exact-tag-commit>",
    "releaseId": 0,
    "tag": "v0.1.0",
    "tagObjectSha": "<direct-annotated-tag-object-sha>"
  }
}
```

The snippets contain rejected placeholders and are templates only. IDs must be
positive integers, SHAs lowercase and exact length, the observer must equal the
policy operator by numeric ID/type and case-insensitive login, and the current
phase observation must be no more than 24 hours old. The immutable tag's
`final-pre-tag` records are re-read later only as strict historical baselines;
their original freshness was required by the final-pre-tag gate and does not
create a 24-hour whole-release deadline. The manifest binds current record
digests to its `expectedCommit`, and the approval-only direct successor binds
that observed master externally, avoiding an impossible self-referential HEAD
field inside a tracked JSON blob.

All release-control timestamps use canonical UTC (`YYYY-MM-DDTHH:MM:SSZ`) and
must preserve this nondecreasing chronology:

```text
final manuals observedAt ≤ final E collectedAt ≤ pre manuals observedAt ≤ pre manifest collectedAt ≤ approval approvedAt
```

When the two manual records in a phase have different observation times, both
must satisfy the applicable side of the inequality. Equality is accepted; a
timestamp inversion invalidates the attempt.

## Closed JSON schema

The block below is intentionally invalid and must not be copied as evidence.
Placeholders, `false` gates, and a `pending` decision are rejected. A real record
has exactly these keys and no duplicates or extensions:

```json
{
  "schemaVersion": "desk-setup-switcher.publication-approval/v1",
  "subject": {
    "repository": "GGULBAE/desk-setup-switcher",
    "tag": "v0.1.0",
    "commit": "<exact-tag-commit>",
    "remoteControlsObservedMasterCommit": "<pre-approval-master-commit>",
    "releaseId": 0,
    "candidateOriginRunId": 0,
    "candidateOriginRunAttempt": 1,
    "candidateArtifactId": 0,
    "candidateArtifactSHA256": "<candidate-archive-sha256>",
    "finalDMGSHA256": "<final-dmg-sha256>"
  },
  "gates": {
    "remoteControlsStable": false,
    "signedNotarizedStapled": false,
    "exactNineAssetsAndAttestations": false,
    "immutableReleases": false,
    "cleanQuarantinedLifecycle": false,
    "threeExternalBetas": false,
    "zeroPublicP0P1": false,
    "zeroConfidentialP0P1": false,
    "publicSurfaceReady": false
  },
  "evidence": {
    "releaseEvidenceSHA256": "<sha256>",
    "remoteControlsEvidenceSHA256": "<sha256>",
    "cleanLifecycleSHA256": "<sha256>",
    "externalBetaReportSHA256": ["<sha256-1>", "<sha256-2>", "<sha256-3>"],
    "publicBlockerQuerySHA256": "<sha256>",
    "confidentialBlockerSignoffSHA256": "<sha256>",
    "publicSurfaceSHA256": "<sha256>"
  },
  "approval": {
    "decision": "pending",
    "releasePublication": false,
    "approvalMode": "one-maintainer",
    "approverLogin": "<github-login>",
    "publisherLogin": "<github-login>",
    "approvedAt": "<canonical-utc-time>",
    "expiresAt": "<canonical-utc-time-within-24-hours>"
  }
}
```

`independent-review` requires different approver and publisher logins.
`one-maintainer` requires the same login and is an explicit governance
limitation, not a two-person review claim. `releasePublication` must be true.
This record grants no site-publication
authority. Site activation remains a later, separate, reviewed
`site/release-publication.json` change after the immutable Release is visibly
public and still requires the user's final approval.

The validator proves the record's exact shape, identifiers, digests, booleans,
actors, and time window. It does **not** interpret the documents named by the
evidence digests or prove that their claims are true. Reviewers must inspect
those protected evidence records before setting a gate to true.

`remoteControlsEvidenceSHA256` is the SHA-256 of the exact
`remote-controls-pre-publication.json` manifest added beside this approval. The
manifest binds the observed pre-approval `master`, exact tag commit, exact draft
Release ID, all three workflow blobs and two anchor reads, the complete active
workflow inventory, both environment API projections, and both manual evidence
digests. The publication helper validates that closed schema before validating
this digest; the approval validator does not independently interpret the
underlying Settings screenshots or token-scope record.

## Publication sequence

1. Establish clean commit **A** on the effective remote `master`. A contains
   both fresh `final-pre-tag` manual records and all three reviewed workflow
   blobs. Wait for exact-A CI and keep remote `v*` refs and Releases empty.
2. From a clean, complete, non-shallow checkout of A, run the final-pre-tag
   two-pass gate with an absent output path outside the repository in an
   owner-owned mode-0700 directory. Preserve the exact resulting mode-0600
   `remote-controls-final-pre-tag.json` bytes as external evidence **E**.
3. Create exactly one **annotated** `v0.1.0` tag object locally, targeting A.
   Its entire message must bind E as
   `remote-controls-final-pre-tag-sha256: <E-SHA-256>`. Record the direct tag
   object SHA and peeled commit A. Do **not** push, recreate, move, or force the
   tag at this stage.
4. Create commit **B** as the direct single-parent child of A. B adds only the
   unchanged E bytes at
   `docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json` as an
   ordinary `100644` blob; no other path may change.
5. Integrate B into `master` with a fast-forward, rebase, or one-commit squash
   only when the resulting history still contains the exact direct
   single-parent A→B edge and the exact add-only E blob. A merge commit is
   forbidden. If integration rewrites B, recheck the resulting B from scratch;
   the recorded local tag object must still target A and bind the same E.
6. Wait for exact-B master-push CI, then rerun the A→B semantic/history check.
   It must prove the single introduction of E, unchanged E bytes through the
   current first-parent tip, the exact annotated-tag digest binding, and
   identical `.github/workflows` and `scripts/release` trees from A through the
   checked tip.
7. Obtain a separate, recorded authorization to push the release tag. Only then
   push the already recorded annotated tag object for the first time. The
   remote object SHA and peeled A commit must match exactly; never create a new
   object during push, move the tag, or use a force update.
8. Build one candidate in the protected `release-candidate` environment and
   retain its attempt-1 origin artifact identity.
9. Prepare the exact draft prerelease from that artifact. Do not rerun the
   origin build.
10. Complete the clean-download lifecycle, three external beta reports, both
    zero-blocker decisions, and final public-surface review for the same DMG.
11. Create new protected screenshot/review-note bundles, replace both manual
    JSON blobs with fresh `pre-publication` phase challenges and distinct source
    digests in one reviewed docs-only master commit, and wait for that exact
    commit's CI. The annotated tag does not move.
12. Start the Settings single-writer freeze. From the clean refreshed-manual
    commit, run `scripts/release/verify-remote-controls.sh --phase pre-publication
    --release-commit <peeled-commit> --release-id <id>`. It writes only the
    normalized manifest after two identical complete observations.
13. Create one direct-successor commit that adds exactly
    `remote-controls-pre-publication.json` and `publication-approval.json`.
    Review it, wait for its exact master-push `Verify macOS app` and `Verify
    public site and release assets` CI jobs to pass, and keep the freeze active.
14. Confirm the canonical UTC chronology `final manuals observedAt ≤ final E
    collectedAt ≤ pre manuals observedAt ≤ pre manifest collectedAt ≤
    approval approvedAt`, then dispatch `Publish
    approved signed release` from the exact `v0.1.0` tag and supply the exact tag
    commit, Release ID, origin run/artifact identities and digests, approval
    commit/digest, actors, and confirmation phrase.
15. Approve the `release-publication` environment only after comparing those
    inputs with the protected evidence. The workflow run must be attempt 1;
    never use GitHub's rerun command for publication.
16. The workflow requires one repository Release—the named draft—verifies its
    metadata and all nine assets twice, confirms immutable Releases are enabled,
    validates both named jobs from the approval commit's exact successful
    master-push CI, downloads
    every asset before mutation, performs the exact-ID PATCH, confirms
    immutability, and downloads and verifies every public asset again. A later
    run never adopts a pre-existing public Release. Only the same live process
    that sent the PATCH may resolve a missing/malformed PATCH response by an
    immediate exact public-state read.
17. Only after the canonical public URL and assets pass the clean-link check may
    a separate reviewed change switch the site state from `holding` to
    `published`. Deployment and announcements still require the user's final
    approval.
18. Keep the freeze through the workflow's final public download verification.
    After success, revoke the release-specific fine-grained PAT and remove or
    rotate `RELEASE_ADMIN_READ_TOKEN`. Record only a read-only Settings
    confirmation that the old credential is no longer active; never log its
    value. End the freeze only after this cleanup evidence is retained.

Any ambiguity observed before the PATCH prevents the mutation. GitHub provides
no compare-and-swap Release publish operation, so a change inside the final
GET-to-PATCH window can only be detected by the mandatory post-publication
reads; in that case the workflow fails after the immutable Release is already
public and cannot roll it back. Do not edit, replace, delete, or republish it;
follow the patch-release incident runbook. `HUP`, `INT`, `QUIT`, or `TERM`, a
workflow cancellation, runner/host loss, unavailable or incomplete logs, or
any recovery outside the same live workflow process is incident-only. It is
refused as an automatic retry even when the interruption appears to precede the
PATCH.

## Failed-attempt renewal

The approval JSON is a time-bounded authorization for one exact candidate, not
an enforceable one-use reservation. Reuse is eligible only when a named normal
fail-closed exit emitted `SAFE_PRE_PATCH_FAILURE`, the same complete Actions
log contains no `PATCH_ATTEMPT_BEGIN`, and the runner plus helper process tree
then ended normally. Marker absence is never proof of non-entry. `HUP`, `INT`,
`QUIT`, `TERM`, workflow cancellation, runner/host loss, unavailable or
incomplete logs, or any failure at/after `PATCH_ATTEMPT_BEGIN` is ambiguous and
incident-only. For an eligible normal failure, a new read-only exact-ID GET must
show the same draft/tag/assets.
Recheck `master`,
the annotated tag object and peeled commit, all assets, current manual evidence,
immutable Releases, and every frozen Settings surface. If the same approval
and current manual records remain within their respective windows and nothing
changed or is suspected to have changed, a **new** attempt-1 dispatch may reuse
that approval; it still requires a new `release-publication` environment
approval. Never use GitHub's rerun command.

If the approval or manual evidence expired, or any frozen surface may have
drifted, create a new evidence attempt. Use the next unused, exactly three-digit
ASCII attempt number `NNN` from `001` through `999` and archive exactly these
four fixed-path files:

```text
docs/evidence/releases/v0.1.0/attempts/NNN/remote-controls-pre-publication.json
docs/evidence/releases/v0.1.0/attempts/NNN/publication-approval.json
docs/evidence/releases/v0.1.0/attempts/NNN/release-candidate-admin-bypass.json
docs/evidence/releases/v0.1.0/attempts/NNN/release-publication-admin-token-scope.json
```

The attempt directory and all four targets must be absent and untracked; any
existing path makes the renewal invalid. In one reviewed docs-only commit, use
`git mv` for exactly those four files and require the diff to contain only four
byte-preserving renames into the same `NNN` directory. Each archived byte stream
must equal `git show <prior-approval-commit>:<original-fixed-path>`, where the
prior approval commit is the exact SHA supplied to the ended dispatch. Never
overwrite, edit, or reuse an attempt directory. In a later reviewed docs-only
commit, capture new protected bundles and add fresh phase-bound manual records
at their fixed paths, then wait for exact-commit CI. Run a new two-pass
pre-publication snapshot, then create the usual direct-successor commit that
adds only new fixed-path manifest/approval files with new times and digests.

If the Release is public, a PATCH may have been sent, or its outcome is
ambiguous after the originating process ended, reapproval and automatic retry
are forbidden. Preserve state and use read-only incident review; do not edit,
replace, delete, move the tag, or claim a later workflow recovered the run.
Retain only the bounded read access needed for that review, then revoke the PAT
and remove or rotate the protected secret with a value-free Settings
confirmation.

## Authoritative GitHub references

- [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
- [Repository immutable-release setting API](https://docs.github.com/en/rest/repos/repos?apiVersion=2026-03-10#check-if-immutable-releases-are-enabled-for-a-repository)
- [Release API](https://docs.github.com/en/rest/releases/releases?apiVersion=2026-03-10)
- [Manually running a workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Using `GITHUB_TOKEN` in a workflow](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)
