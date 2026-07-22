# Governance and maintainership

Desk Setup Switcher is a small maintainer-led project. Governance favors a narrow, auditable product over feature volume.

## Current roles

Until additional people are explicitly recorded, [@GGULBAE](https://github.com/GGULBAE) is the repository maintainer, triage owner, security contact, and release approver.

| Role | Responsibility | Authority |
| --- | --- | --- |
| Maintainer | Product scope, architecture, roadmap, contributor review, and conflict resolution | Merge or decline changes; appoint or remove delegated roles |
| Triager | Reproduce and classify issues, request redaction, identify support versus security reports | Apply labels and recommend priority; cannot publish a release |
| Security responder | Receive private reports, coordinate remediation and disclosure | Prepare advisories and fixes; never move report details to public issues without reporter coordination |
| Release operator | Build the fixed protected predecessor and final candidate, sign/notarize each, collect evidence, and prepare or additively resume only the final candidate's exact draft release | Access the protected release environment and create only each separately approved annotated tag; may append only missing byte-identical assets to the exact `v0.1.0` draft and can never edit/delete/publish it, move/delete either tag, replace an existing asset, or create a GitHub Release for `v0.0.9` |
| Release approver | Compare both tagged commits and origin artifacts, the final draft, checks, upgrade evidence, and release ledger | Approve each bounded tag/build transition and the final publication, or stop the release |
| Release publisher | Dispatch the exact approved publication record through the protected publication environment | May publish only the named byte-verified draft Release; cannot build, sign, tag, edit, replace, delete, or deploy the site |

Delegation must be recorded in a pull request that updates this file or a future `CODEOWNERS`/maintainers file. Assignment to an issue alone does not grant merge, security, secret, or release access.

## Decisions

Routine fixes use pull-request review and repository checks. A change that expands system mutation, permissions, data collection, outbound network access, persistence format, public compatibility, signing entitlements, or release infrastructure requires an explicit maintainer decision recorded in the pull request or a linked issue.

The non-negotiable boundaries are local-only operation, no account/cloud/telemetry, explicit Review & Apply, typed verification and rollback, public macOS APIs, redacted evidence, and no live mutation in ordinary tests or CI. Changes that conflict with those boundaries are out of scope unless this governance document and the product contract are deliberately revised first.

## Triage

Public reports are handled as best effort. Safety, data loss, unsafe rollback, import-path handling, credential exposure, and release-integrity problems take precedence over feature requests. Suspected security reports are removed from public triage as soon as practical and redirected according to [SECURITY.md](SECURITY.md); contributors must not ask reporters to add exploit details publicly.

Release-blocker severity follows [the distribution policy](docs/DISTRIBUTION.md): P0 is a stop/withdraw condition for security/privacy compromise, data loss, release-integrity failure, unsafe persistent mutation, or loss of the documented recovery route; P1 blocks release when the official candidate cannot safely install, upgrade, launch, migrate/recover, uninstall, or complete the supported three-step flow on the supported platform. The triager proposes severity. The maintainer decides public product severity, and the security responder decides confidential security severity. Before release approval, the maintainer must record zero unresolved public P0/P1 issues and the security responder must record only a yes/no statement that no confidential P0/P1 blocker remains. Private counts and details are never copied into the public ledger.

## Releases

Release preparation follows [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). The release operator must use the protected release environment to retain two immutable attempt-1 origins: `v0.0.9`/build 1 as the protected-beta predecessor and `v0.1.0`/build 2 as the final public-beta candidate. Only the latter may prepare a draft. The release approver verifies both annotated tag objects and commits, both version/build and origin identities, CI, signature/notarization/stapling, checksums, provenance, SBOM, the predecessor-to-final upgrade, support claims, exact downloaded/quarantined lifecycle, three external beta reports, and zero-blocker sign-offs before publication. The human-readable evidence uses [the release evidence template](docs/RELEASE-EVIDENCE-TEMPLATE.md), and the final machine-bound decision follows the separate [public release approval contract](docs/PUBLICATION-APPROVAL.md).

The local workspace's proposed signed-candidate workflow uses three isolated manual tag-ref dispatches through the same reviewed workflow and protected `release-candidate` environment. The first `build-candidate` binds annotated `v0.0.9` to its exact commit, signs/notarizes/staples build 1 once, and persists its exact nine assets in an immutable attempt-1 predecessor origin. A second `build-candidate` does the same for annotated `v0.1.0`, build 2, and a distinct final origin. Only a separate `prepare-draft` run for `v0.1.0` may name the final origin run, artifact ID, and archive SHA-256; it verifies the raw archive, all nine files, and all three attestation bundles before creating or additively resuming the exact final draft. It can add only missing byte-identical assets and can never rebuild, clobber, edit, delete, or publish. Neither origin build run may be rerun because GitHub full reruns remove its artifact; draft-run reruns restore only from the final origin. A separate manual publication workflow restores and verifies both origins, then proposes an exact approval-record-bound `draft → public prerelease` transition through `release-publication`; it cannot sign, tag, alter assets, create a predecessor Release, or deploy the site. All paths are unpushed and unproven with real credentials or remote protection. The effective workflow on `origin/master`, inspected read-only on 2026-07-18 and rechecked on 2026-07-20, is older and can create a public unsigned Release from a `v*` tag without a protected environment. No release tag may be pushed until that effective remote path is removed and both reviewed environments and workflows are configured, policy-bound, and proven.

The repository currently has one maintainer, so independent two-person approval is not claimed. Before the first public beta, the repository administrator must configure the protected release environment and document the actual approver path. GitHub immutable releases must be enabled before publication. A bad public release is handled with [the incident runbook](docs/RELEASE-INCIDENT-RUNBOOK.md): mark it affected or discontinued, preserve its immutable tag/assets/evidence, and recover with a new patch version.

### Repository settings still required

Read-only GitHub API checks on 2026-07-18 and 2026-07-20 found no configured repository environments, no protection on `master`, disabled Discussions, and disabled private vulnerability reporting. The support issue form is the deliberate alternative to Discussions, but the other controls remain public-launch blockers:

1. Create and protect the `release-candidate` and `release-publication` environments. Restrict `release-candidate` to the exact `v0.0.9` and `v0.1.0` tags, restrict `release-publication` to only `v0.1.0`, and configure the real required-reviewer and publisher paths. Naming an environment in workflow YAML does not configure those protections by itself.
2. Protect `master` with the required CI checks and no standing bypass actor. Emergency recovery requires a separately approved ruleset change or disable; it is not a configured bypass.
3. Protect release tags with separate rules: the approved release operator may bypass creation only, while update and deletion have no bypass. Creation authority must never permit moving or deleting an existing release tag.
4. Enable private vulnerability reporting, update the Security contact link to the private advisory form, and test it before announcing the beta.
5. Enable immutable releases and confirm the setting through a read-only query before publication.
6. Apply the exact Actions, repository-metadata, label, credential-scope, and phase-specific tag/Release prerequisites specified by [Distribution](docs/DISTRIBUTION.md), configure the authoritative v3 policy with all four workflow identities—including the disabled legacy tombstone—and the reviewed environment/admin-read secret identity, then pass `predecessor-pre-tag`, `final-pre-tag`, and `pre-publication` with their separate Settings checks.

Do not push a public release tag merely to test these controls; exercise them first with the repository's documented candidate procedure.

## Conduct and licensing

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Contributions are accepted under the [MIT License](LICENSE). Maintainers may close contributions that cannot be verified safely, disclose sensitive data, or exceed the documented product scope.
