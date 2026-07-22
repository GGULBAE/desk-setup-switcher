# Remote release controls audit

Original observation: 2026-07-18 16:04 KST

Latest read-only recheck: 2026-07-22 13:48 KST

## Outcome

The GitHub repository is public, but it is **not ready for a release tag**. The
workflow effective on the default branch starts for every pushed `v*` tag and,
after its version guard, can publish the current unsigned `v0.1.0` DMG. No tag or
Release exists, so the unsafe path has not run.

This was a read-only audit. It did not push a branch, create or move a tag,
change a workflow setting, create an environment, inspect credential values,
publish a Release, or deploy the site.

## 2026-07-22 read-only recheck and containment plan

At 2026-07-22 13:48 KST, authenticated GitHub GET/list requests again confirmed
the stop condition observed at that time. Remote `master` was
`1489b7fcb41ffa7e55a43ed65e6befc538838140`; the audited local release-control
source `de4f805cfadf5fdfd1266d07286d27192794ca33` was its descendant, 39 commits
ahead. Workflow `311269012` was the active historical **Release** workflow. The
remote workflow inventory contained only CI and that legacy Release workflow;
the signed-candidate and publication workflows were local and unpushed.

That GET-only observation found:

- `master` was unprotected (`protected:false` and the branch-protection request
  returned 404), with zero repository rulesets;
- zero environments, repository Actions secret names, repository Actions
  variable names, `v*` tags, GitHub Releases, and Release-workflow runs;
- immutable Releases and private vulnerability reporting disabled;
- all Actions allowed with full-SHA pinning unenforced;
- no Homepage, topics, Pages site, or `needs-triage` label, Discussions disabled,
  and the description still advertising mouse and keyboard; and
- the repository was still public with an MIT license and Issues enabled, the
  default workflow token read-only, secret scanning and push protection
  enabled, Dependabot security updates enabled, and the existing remote-master
  CI successful.

The corrected GET-only containment planner completed two stable observations
and created the private receipt
`legacy-workflow-containment-plan-de4f805-20260722.json`. Its parent directory
was mode 0700 and the file was mode 0600. The receipt bound the exact local HEAD
and all four expected tool blobs, recorded the workflow as active with zero tags
and Releases, and had plan digest
`bb53444e29871dd077d975128f0d41299d484d694429939a5e9f7daa11e0d4e6`.
A separate `validate-plan` invocation using the same checked-in validator
accepted those exact private bytes.
Apply compares the current clean checkout HEAD and tool blobs with the receipt,
so this receipt is accepted only from a clean checkout of
`de4f805cfadf5fdfd1266d07286d27192794ca33`; any later HEAD must create and
review a new GET-only plan.

The receipt remained private, was not committed, and is planning evidence only.
No apply operation or PUT occurred, and this recheck did not push, create or
move a tag, dispatch a workflow, publish a Release, or make any other remote
mutation. The active legacy workflow was therefore not contained by this
recheck.

## 2026-07-21 read-only recheck

Authenticated GitHub GET/list requests confirmed that the stop condition is
unchanged: remote `master` is still
`1489b7fcb41ffa7e55a43ed65e6befc538838140`, workflow `311269012` is still the
active historical **Release** workflow, and there are still zero `v*` refs,
Releases, rulesets, environments, repository secret names, and repository
variable names. `master` protection is absent, immutable Releases and private
vulnerability reporting are disabled, the `needs-triage` label and Pages site
are absent, and the public description still advertises mouse and keyboard.
No credential value was queried or retained.

The first bounded invocation of the dedicated GET-only containment planner
stopped before a complete observation and created no receipt because GitHub CLI
2.95 rejects `--slurp` together with `--jq`. It made no PUT or other remote
mutation. The local fix retains the CLI-side minimal-field projection, streams
paginated JSON lines into strict duplicate-key-aware canonicalization, handles
a trailing-slash `TMPDIR`, and passes 306 deterministic containment assertions,
including multi-page, malformed, duplicate-key, inconsistent-total, truncated,
drift, and uncertainty cases. A private plan receipt is still planning evidence,
not proof that the active workflow was disabled.

The containment helper assumes a trusted local account, checkout, and local
Git, Ruby, and `gh` toolchain. Its descriptor/no-follow, Git-blob, streaming
hash/HMAC, root-owned empty `gh` configuration, minimal child-environment, and
signal controls defend capture-path consistency and replacement/truncation
races during an authorized invocation. They do not sandbox a malicious
same-UID process, hostile token-holding caller, compromised runtime/checkout,
or substituted toolchain. The internal operation/plan authorization binding is
an accidental-misuse guardrail, not authentication of a hostile caller.

## 2026-07-20 read-only recheck

The release-control implementation advanced after the original observation, so
the repository and the exact local release boundary were queried again before
requesting any remote change. The unsafe remote state is unchanged. This recheck
used authenticated GitHub GET/list operations and a refreshed `origin/master`;
it did not run the final remote-controls collector because the authoritative
policy correctly remains `configured:false` until the real protection and actor
decisions exist.

| Boundary | Rechecked value |
| --- | --- |
| Remote default branch | `master` at `1489b7fcb41ffa7e55a43ed65e6befc538838140`; still the ancestor of the local branch |
| Audited earlier release-control baseline | `8951f2eff50a5f95657ff9f11a34eebb3bd0203e`; 26 commits ahead of remote `master` before its documentation-only recheck amendment |
| Pre-repair local branch tip | `01db3ac3eb74653302fa35386044c114e27bdedd`; 29 commits ahead of remote `master` before the two-CI-job gate repair and this recheck amendment; the three reviewed workflow blobs below were unchanged |
| Local reviewed workflow blobs | CI `ab5228895a4da48e8b88ef792e1e043ce00ad938`; candidate/draft `8823e73221d6af038d3469880fb0b8e7a36140e1`; publication `b380c279d1e222ee7ea1bd5a941ef30ee6eb5079` |
| Effective remote workflows | CI `311269011` active; historical Release `311269012` active; no publication workflow exists remotely |
| Effective remote workflow blobs | CI `7ba41d81c2e5d917d35d598c68a0791ea97081fc`; unsafe Release `0648b71f683fa0bdcc430d02a7e16d32e0ee0c42` |
| Protections and release gates | No `master` protection, ruleset, or environment; immutable Releases and private vulnerability reporting disabled |
| Actions and security | All Actions allowed and full-SHA enforcement disabled; default workflow token read-only and PR-review approval disabled; secret scanning, push protection, and Dependabot security updates enabled |
| Names and public boundary | Repository secret/variable name lists empty; environment credential-name lists unavailable because no environment exists; no tag or Release; one administrator collaborator; stale mouse/keyboard description, no topics or Homepage, Discussions disabled, and no `needs-triage` label |
| Pre-repair local closure | At `01db3ac`, `make verify` passed 2,961 non-live checks/assertions; unsigned development-evidence DMG SHA-256 `0e37ca3c2bb9826cb57b227660a10376ae483497ad5b035e81e3fb3725202681`; not installed, launched, uploaded, or published |
| Public-surface and containment closure | That closure state passed `make verify` with 3,199 non-live checks/assertions, including 178 v2 policy, 69 v2 collector, 129 collector-wrapper, 424 publisher, 152 legacy-workflow-containment, and 203 shell/workflow guard assertions; unsigned development-evidence DMG SHA-256 `6cd2a3d512c9656d71fa916d3a3a0460894f8351d335fb7217ded4920b808805`; not installed, launched, uploaded, or published; the containment helper did not contact GitHub |

The recheck changes no conclusion below: do not push a `v*` tag, dispatch a
release workflow, or treat the local mock/structural evidence as a protected
remote result. The original table is retained as historical evidence; this
section is the 2026-07-20 pre-mutation snapshot; the latest snapshot appears
above.

## Audited identities

| Boundary | Observed value |
| --- | --- |
| Repository | `GGULBAE/desk-setup-switcher`, public |
| Default branch | `master` |
| Remote `master` | `1489b7fcb41ffa7e55a43ed65e6befc538838140` |
| Reviewed local implementation tip | `66094848a0876c9be20094ce06fdec7b9fcbdb61` |
| Audited implementation ancestry | `6609484` is 16 commits ahead of remote `master`; this audit record follows it only on the local feature branch |
| Remote release-workflow blob | `0648b71f683fa0bdcc430d02a7e16d32e0ee0c42` |
| Reviewed local release-workflow blob | `34bdbad52beac8449a23e271de8a689ad6bafc67` |
| Latest remote `master` CI | [run `29387285414`](https://github.com/GGULBAE/desk-setup-switcher/actions/runs/29387285414), successful for `1489b7f` |
| Audit-branch local closure | Non-live `make verify` passed 908 checks/assertions; regenerated ad-hoc DMG SHA-256 `16c8ef3ede9630e15afc9d6627434bcd09d0a2ec4e1c9fc208d5dded9be82de7`; not installed or launched |

The audit refreshed `origin/master`, compared the workflow blobs, and queried
the current GitHub REST surfaces. Error responses below are evidence of missing
configuration, not failed retries.

## Stop condition — P0

The release workflow on remote `master` currently:

- triggers automatically for every pushed `v*` tag;
- receives `contents: write`;
- runs the development `make verify` path and produces the ad-hoc DMG; and
- after its current `v0.1.0` tag/version guard, calls `gh release create` without
  `--draft`, `--prerelease`, a protected environment, Developer ID signing,
  notarization, stapling, SBOM, provenance, redownload verification, or
  publication approval.

The reviewed local signed-candidate workflow instead uses manual
`workflow_dispatch` and exact existing annotated tag/commit pairs. Separate
`build-candidate` runs create and retain the signed/notarized/stapled
`v0.0.9`/build-1 predecessor origin and `v0.1.0`/build-2 final origin. Only a
third `prepare-draft` dispatch may restore the final origin and create or
additively resume its exact draft prerelease. The predecessor never creates a
Release. This workflow is not effective remotely yet.

**Invariant:** do not create or push either remote `v*` tag until GitHub serves
the reviewed manual workflow from the default branch and a read-only check
proves that the old automatic publisher cannot run. The predecessor annotated
tag targets clean P and binds the later add-only E0 evidence introduction; the
final annotated tag targets clean F after P→P1 has landed and binds the later
add-only E1 introduction. Each local tag object is reviewed and separately
approved before its first push, and neither tag may be moved or deleted.

## Current repository controls

| Control | Read-only evidence | Release effect |
| --- | --- | --- |
| Default-branch protection | `GET /branches/master/protection` → `404`; `master` is not protected | P1: no PR/check/force-push boundary |
| Repository rulesets | `GET /rulesets` → `200 []` | P1: no branch or tag creation/update/deletion rule |
| Environments | `GET /environments` → zero; `release-candidate` → `404` | P1: the YAML name supplies no reviewer or secret protection |
| Repository secrets/variables | Both name lists are empty | Expected before setup; the signed path cannot run |
| Environment secrets/variables | Environment does not exist | P1: no protected signing/notary configuration |
| Immutable releases | `GET /immutable-releases` → `enabled: false` | P1: future Release immutability is not enforced |
| Private vulnerability reporting | `enabled: false` | P1: the private reporting route is unavailable |
| Tags and Releases | zero tags, zero `v*` refs, zero Releases | Good: the unsafe publisher has not executed |
| Actions token default | `read`; Actions cannot approve PR reviews | Good least-privilege default |
| Allowed Actions | `all`; full-SHA enforcement disabled | P2: checked-in actions are pinned, but policy does not enforce it |
| Secret scanning | scanning and push protection enabled | Good |
| Dependabot security updates | enabled | Good |
| Collaborators | only `GGULBAE`, administrator | An independent required reviewer is not currently available |

GitHub environment secrets are unavailable until configured protection is
satisfied, but merely naming an environment in YAML does not create those
protections. Rulesets can protect branches and tags; immutable releases apply
only to future Releases and must be enabled before publication. See GitHub's
[environment](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments),
[ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets),
[private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository),
and [immutable release](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
documentation.

## Current public surface

| Surface | Remote state | Required action |
| --- | --- | --- |
| Description | Still advertises Mouse and Keyboard switching | Replace with the approved Display/Audio/Network three-step description |
| Topics | Empty | Add the exact reviewed set from `LAUNCH-COPY.md` |
| Homepage | Empty | Keep empty until the deployed HTTPS site passes clean-link review |
| Discussions | Disabled | Keep disabled unless the support policy deliberately changes |
| Support route | Remote tree has no `SUPPORT.md` or support-question form | Merge the reviewed local files before promotion |
| Security contact link | Points at private advisories while reporting is disabled | Enable and test private reporting before announcing the beta |
| Issue labels | Forms request `needs-triage`, but that label does not exist | Create the label or remove it from the forms before relying on triage |
| Pages/deployment | No Pages site or deployment | Site publication remains a separate approval |
| Social preview | Not verifiable through the allowed REST GET surface | Record a bounded manual settings-page check before launch |

## Minimum safe remote mutation sequence

Every numbered phase below requires explicit approval before it changes GitHub.
No phase authorizes a tag, signed workflow run, public Release, site deployment,
or promotional post unless that action is named separately.

1. **Contain the old publisher.** Keep the global `v*` tag freeze. First run the
   local GET-only `plan-legacy-workflow-containment` target with the exact remote
   `master` SHA and an absent external receipt path under an owner-mode-0700
   directory; review its mode-0600 receipt and digest. Under a new explicit
   approval, provide that exact receipt/digest/SHA, the mutation opt-in, and the
   exact typed workflow-ID/SHA confirmation to
   `apply-legacy-workflow-containment`. It may send one fixed disable PUT only;
   require its mode-0600 success receipt to show stable pre/post observations
   and `disabled_manually`. An already-disabled result must record zero PUT.
   Any exit 75 or missing result is ambiguous incident evidence: do not retry or
   enable; preserve the tag freeze and perform a separate read-only review.
2. **Prepare bootstrap protections without secrets.** Create an active `master`
   ruleset requiring a pull request and the already-observed GitHub Actions
   check `Verify macOS app` (GitHub Actions app ID `15368`), conversation
   resolution, and blocked force pushes/deletion. The new `Verify public site
   and release assets` job has no remote check history yet, so this is a
   temporary containment rule and authorizes no merge. Require one PR approval
   only if a second trusted reviewer is appointed; otherwise use zero required
   approvals and document the weaker one-maintainer path. Do not require signed
   commits for this integration because the reviewed pending commits are
   unsigned.
3. **Protect tags without a mutable-tag bypass.** Create one active `v*`
   creation ruleset whose only bypass is the approved release-operator User,
   plus a second active `v*` ruleset that blocks update and deletion with no
   bypass actor. Do not grant the operator a path to move or delete an existing
   release tag, and do not test either rule with a release tag.
4. **Create the release gates.** Create both `release-candidate` and
   `release-publication`. Restrict `release-candidate` to exactly `v0.0.9` and
   `v0.1.0`; restrict `release-publication` to only `v0.1.0`. Configure the
   required reviewers and publisher, explicitly decide self-review and
   administrator-bypass behavior, and leave both without credentials until
   read-back proves the protection.
5. **Push code only to a feature branch.** After local verification and explicit
   approval for that push, record and push the exact reviewed release-controls
   HEAD. Use `--no-follow-tags`; do not update `master` directly and do not
   create either protected release tag during integration.
6. **Open, strengthen, and verify a PR.** Target `master` and let the PR run both
   updated read-only jobs. Read back the new `Verify public site and release
   assets` check and its GitHub Actions app ID, then update the still-active
   `master` ruleset before merge so its exact required-check set is `Verify macOS
   app` plus `Verify public site and release assets`, both from app ID `15368`.
   Read back the effective rule and require both jobs to pass; the first runs
   `make verify` plus the complete history/asset audit and the second verifies
   the site and release media. Preserve the reviewed commit ancestry with a
   merge commit if the evidence continues to name those commit IDs.
7. **Prove both merged workflow identities.** Wait for post-merge CI, then read
   both paths back from GitHub. `.github/workflows/release.yml` must be the
   reviewed fail-only **Retired legacy release workflow**, remain
   `disabled_manually`, have no token permissions or release command, and never
   be re-enabled. `.github/workflows/signed-release-candidate.yml` must be the
   distinct reviewed manual candidate path. Confirm the unsafe tag trigger and
   unsigned publisher are absent and tags/Releases remain empty.
8. **Activate only the new signed-candidate workflow.** Under a new explicit
   approval, activate `.github/workflows/signed-release-candidate.yml` without
   dispatching it. Read its state and default-branch content back; require
   `active`, the reviewed blob, and `workflow_dispatch` as the only trigger.
   Read the legacy path again and require it to remain disabled. No procedure in
   this repository authorizes re-enabling the legacy workflow.
9. **Finish repository controls.** Enable private vulnerability reporting and
   immutable Releases. Require selected GitHub-owned Actions and full-SHA
   pinning, a read-only default workflow token, and no workflow PR-review
   approval permission. Create `needs-triage`, apply the approved
   description/topics/Homepage and disabled-Discussions state, and read every
   value back.
10. **Configure protected values without exposing them.** Add the four signing
    variables and three signing/notarization secrets below directly to
    `release-candidate`. Add only the shared `DEVELOPER_ID_APPLICATION` and
    `APPLE_TEAM_ID` variables plus the separate minimum-scope
    `RELEASE_ADMIN_READ_TOKEN` secret to `release-publication`. Never paste
    values into issues, PRs, task messages, commands, fixtures, or logs.
11. **Synchronize evidence and anchor the v3 policy.** After read-back confirms the
    changed settings, update `SECURITY.md`, support/governance/distribution/
    readiness documents, and the completion ledger through another reviewed PR.
    Populate every authoritative-policy field from reviewed read-only evidence:
    repository numeric/node identity and approved metadata/state; CI,
    signed-candidate, publication, and disabled-legacy workflow
    IDs/names/paths/blobs; both release environments; both fixed tags/builds;
    release and both CI-check identities; actor
    IDs/logins/types, and the approval mode/count/self-review setting. Do not copy
    synthetic fixture identities. Review and merge that policy with all four
    workflow blobs it names, then wait for exact-commit CI.
12. **Run the predecessor-pre-tag read-only gate.** Through the protected
    reviewed path, establish the clean `v0.0.9`/build-1 source commit with two
    fresh closed-schema `predecessor-pre-tag` manual records and all four
    reviewed workflow blobs. Wait for exact-commit CI. From a clean, complete,
    non-shallow checkout authenticated as the configured operator with
    repository-admin visibility, run
    `make verify-remote-controls-predecessor-pre-tag REMOTE_CONTROLS_EVIDENCE_OUTPUT=/absolute/private/remote-controls-predecessor-pre-tag.json`
    while remote `v*` refs and Releases remain empty. Preserve the exact
    mode-0600 output and sanitized `manual_gates=2` transcript. The command
    performs only local reads and authenticated GETs.
13. **Bind and build the protected predecessor.** Create one annotated
    `v0.0.9` tag object targeting the build-1 commit with the exact message
    `remote-controls-predecessor-pre-tag-sha256: <digest>`. Record its object SHA
    and peeled commit; do not push it. Create the required direct-child commit
    that adds only the unchanged evidence bytes at
    `docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json` as
    `100644`. Integrate without a merge commit while preserving that exact edge,
    wait for exact CI, and rerun the semantic/history check. Obtain a separate
    tag-push authorization, push only the recorded tag object, then separately
    authorize one attempt-1 `build-candidate` dispatch for `v0.0.9`. Retain its
    exact nine-asset origin; never prepare a draft or GitHub Release for it.
14. **Run the final-pre-tag gate.** Establish the descendant `v0.1.0`/build-2
    source commit with `.github/workflows` and `scripts/release` byte-identical
    to the predecessor tagged commit. Capture fresh `final-pre-tag` manual
    records and wait for exact CI. With exactly the annotated `v0.0.9` ref and
    zero Releases, run
    `make verify-remote-controls-final-pre-tag` with the exact predecessor
    commit, predecessor tag-object SHA, and a new absent external output. The v3
    result must bind the predecessor-pre-tag evidence digest and predecessor
    tag/commit boundary.
15. **Bind and build the final candidate.** Create one annotated `v0.1.0` tag
    object targeting the build-2 commit with the exact message
    `remote-controls-final-pre-tag-sha256: <digest>`. Add only the unchanged
    evidence at
    `docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json` in the
    required direct-child commit, integrate without a merge commit, wait for
    exact CI, and rerun the semantic/history check. Obtain a separate tag-push
    authorization, push only that recorded object, then separately authorize
    the attempt-1 build and final-only draft preparation. Preserve both origin
    artifacts; never rerun either build.
16. **Use the v3 pre-publication path after the draft.** Complete the mandatory
    predecessor upgrade and all lifecycle/beta evidence. Capture new protected
    Settings bundles and replace both manual records with fresh
    `pre-publication` phase challenges for the final tag object/peeled commit and
    the exact final draft Release ID in one reviewed docs-only commit; wait for
    CI. The v3 API manifest separately binds both tags and peeled commits. Freeze
    every release-relevant GitHub Settings surface, run the two-pass
    pre-publication verifier, then add only its manifest and the approval record
    in one direct-successor commit. That approval commit's exact master-push CI
    must pass before dispatch. Every timestamp is canonical UTC and ordered
    across the predecessor-pre-tag, final-pre-tag, pre-publication, and approval
    stages. This v3 lifecycle does not retroactively turn any 2026-07-18,
    2026-07-20, or 2026-07-21 observation into release evidence.

Required protected environment variables:

- `DEVELOPER_ID_APPLICATION`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`

Required protected environment secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_API_KEY_BASE64`

The publication environment contains only the shared non-secret
`DEVELOPER_ID_APPLICATION` and `APPLE_TEAM_ID` variables plus
`RELEASE_ADMIN_READ_TOKEN`, a repository-scoped fine-grained read token with
exactly Actions, Administration, Attestations, Contents, and implicit Metadata
read access. It has exactly six bounded workflow secret references: pinned
checkout, combined two-origin restoration, final-candidate attestation
verification, predecessor tagged-source verification, the publication helper,
and post-publication final-attestation verification. Within the
helper, it is installed only through five tracked, timeout-bounded GitHub
read/download launcher call sites; it is never the publication write token.
No signing/notarization secret is present in `release-publication`.

The repository currently has one collaborator. Turning on prevent-self-review
with only `GGULBAE` as reviewer would deadlock the job. Before remote setup, choose
one of these truthful policies:

- nominate a second trusted GitHub reviewer and enable prevent-self-review; or
- document the one-maintainer approval path, leave prevent-self-review off, and
  retain the separate final publication approval and complete evidence review.

The first option provides the stronger trust boundary.

## Rollback and failure rules

- If PR CI fails, do not merge. Close the PR or delete only its feature branch;
  keep the tag freeze and disabled old workflow.
- If containment apply exits 75, is interrupted after the PUT attempt, or lacks
  a success receipt, do not retry and never enable the workflow. Preserve the
  plan, logs, and remote state; use an independently authorized read-only check
  to determine the actual state while the `v*` tag freeze remains in force.
- If a ruleset or environment policy deadlocks, correct or disable that new
  control before storing credentials. Never test recovery with `v*`.
- If post-merge CI fails, fix forward through another PR. Do not force-push
  `master` and never restore the unsigned automatic publisher.
- If approval cannot proceed, cancel the run and correct the reviewer policy;
  do not use a silent administrator bypass.
- A publication-side `HUP`, `INT`, `QUIT`, `TERM`, workflow cancellation,
  runner/host loss, unavailable or incomplete logs, or any ambiguous PATCH
  outcome is incident-only. Preserve state and use read-only review; never
  automatically retry, adopt a public Release, or infer safety from a missing
  marker.
- If a credentialed candidate fails before its exact nine assets are finalized as
  the immutable attempt-1 origin artifact, preserve the run and start a new
  versioned candidate. Never rerun the origin build: GitHub full reruns remove its
  artifact before jobs execute, and the workflow guard rejects rebuilding it.
- A local post-audit follow-up now proposes a separate `prepare-draft` dispatch
  after that artifact exists. It binds the origin run, artifact ID, and archive
  digest; verifies the raw ZIP, exact files, candidate, and attestations before
  mutation; preserves the origin run/attempt in the manifest; and separately
  records the draft verification run/attempt. Only then may its additive reconciler
  accept exact draft metadata and byte-identical assets or append missing names.
- Any extra or different asset, changed notes/title/state, unavailable artifact,
  origin mismatch, or API ambiguity still requires a new versioned candidate and
  tag. The resume path never clobbers, edits, deletes, publishes, or moves a tag.
  It remains unpushed and unproven until the protected environment and a real
  credential-free recovery rehearsal produce evidence.
- If source, resources, entitlements, or release tooling must change, do not move
  or reuse the tag. Increment the build/version, preserve the failed evidence,
  and start a new candidate.
- A draft verification failure is never permission to publish or replace assets.

## Approval boundary prepared by this audit

The next safe external action is not a release. It is an explicitly approved
remote-containment and PR-preparation phase covering only steps 1–6 above. The
locally mock-tested plan/apply helper narrows step 1 but grants no authority by
itself. This phase
must name the reviewer policy and must continue to prohibit all tag, Release,
site, signing/notarization, installation, live hardware mutation, and promotion
actions.

The local branch now also carries explicit v3 `predecessor-pre-tag`,
`final-pre-tag`, and `pre-publication` verifiers. Their deterministic fixtures
test the intended ready states, while the authoritative policy remains
intentionally unconfigured until its complete repository, signed-candidate,
CI, publication, disabled-legacy, operator, reviewer, publisher, and approval
identity is reviewed;
therefore a live invocation must fail before its first GitHub request today. The
wrapper performs authenticated GETs and projects variable responses to names
before evidence is written; the collector consumes only those name projections,
requires authenticated draft visibility, cross-binds both distinct required
checks to the pinned CI workflow's exact two successful jobs in one run/check
suite, and collects all release-critical
remote observations twice before requiring normalized equality. Only names are
emitted, persisted, normalized, compared, or recorded, and no credential value
is retained in evidence. Even a future API pass
leaves the environment administrator-bypass switch as one separately recorded
Settings-screen gate because the documented REST response does not expose that
state. Direct normalized-evidence policy output remains offline component
evidence and cannot replace steps 12, 14, or 16.
