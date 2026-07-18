# Governance and maintainership

Desk Setup Switcher is a small maintainer-led project. Governance favors a narrow, auditable product over feature volume.

## Current roles

Until additional people are explicitly recorded, [@GGULBAE](https://github.com/GGULBAE) is the repository maintainer, triage owner, security contact, and release approver.

| Role | Responsibility | Authority |
| --- | --- | --- |
| Maintainer | Product scope, architecture, roadmap, contributor review, and conflict resolution | Merge or decline changes; appoint or remove delegated roles |
| Triager | Reproduce and classify issues, request redaction, identify support versus security reports | Apply labels and recommend priority; cannot publish a release |
| Security responder | Receive private reports, coordinate remediation and disclosure | Prepare advisories and fixes; never move report details to public issues without reporter coordination |
| Release operator | Build one candidate, sign/notarize it, collect evidence, and prepare a draft release | Access the protected release environment; cannot silently replace a published tag or asset |
| Release approver | Compare the draft, commit, tag, checks, artifact, and release ledger | Approve publication or stop the release |

Delegation must be recorded in a pull request that updates this file or a future `CODEOWNERS`/maintainers file. Assignment to an issue alone does not grant merge, security, secret, or release access.

## Decisions

Routine fixes use pull-request review and repository checks. A change that expands system mutation, permissions, data collection, outbound network access, persistence format, public compatibility, signing entitlements, or release infrastructure requires an explicit maintainer decision recorded in the pull request or a linked issue.

The non-negotiable boundaries are local-only operation, no account/cloud/telemetry, explicit Review & Apply, typed verification and rollback, public macOS APIs, redacted evidence, and no live mutation in ordinary tests or CI. Changes that conflict with those boundaries are out of scope unless this governance document and the product contract are deliberately revised first.

## Triage

Public reports are handled as best effort. Safety, data loss, unsafe rollback, import-path handling, credential exposure, and release-integrity problems take precedence over feature requests. Suspected security reports are removed from public triage as soon as practical and redirected according to [SECURITY.md](SECURITY.md); contributors must not ask reporters to add exploit details publicly.

Release-blocker severity follows [the distribution policy](docs/DISTRIBUTION.md): P0 is a stop/withdraw condition for security/privacy compromise, data loss, release-integrity failure, unsafe persistent mutation, or loss of the documented recovery route; P1 blocks release when the official candidate cannot safely install, upgrade, launch, migrate/recover, uninstall, or complete the supported three-step flow on the supported platform. The triager proposes severity. The maintainer decides public product severity, and the security responder decides confidential security severity. Before release approval, the maintainer must record zero unresolved public P0/P1 issues and the security responder must record only a yes/no statement that no confidential P0/P1 blocker remains. Private counts and details are never copied into the public ledger.

## Releases

Release preparation follows [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). The release operator must use the protected release environment and prepare a draft from one immutable candidate. The release approver verifies the tag/commit/version/build, CI, signature/notarization/stapling, checksums, provenance, SBOM, support claims, exact downloaded/quarantined lifecycle, three external beta reports, and zero-blocker sign-offs before publication. The protected approval record uses [the release evidence template](docs/RELEASE-EVIDENCE-TEMPLATE.md).

The local workspace's proposed signed-candidate workflow is a manual tag-ref dispatch that references `release-candidate`, binds the tag to an expected commit, and is designed to prepare only a signed/notarized/stapled draft prerelease plus attestations and a workflow artifact. It contains no public publish command, but it is unpushed and unproven with real credentials. The effective workflow on `origin/master`, inspected read-only on 2026-07-18, is older and can create a public unsigned Release from a `v*` tag without a protected environment. No release tag may be pushed until that effective remote path is removed and the reviewed Developer ID path and environment are configured and proven.

The repository currently has one maintainer, so independent two-person approval is not claimed. Before the first public beta, the repository administrator must configure the protected release environment and document the actual approver path. GitHub immutable releases must be enabled before publication. A bad public release is handled with [the incident runbook](docs/RELEASE-INCIDENT-RUNBOOK.md): mark it affected or discontinued, preserve its immutable tag/assets/evidence, and recover with a new patch version.

### Repository settings still required

A read-only GitHub API check on 2026-07-18 found no configured repository environments, no protection on `master`, disabled Discussions, and disabled private vulnerability reporting. The support issue form is the deliberate alternative to Discussions, but the other controls remain public-launch blockers:

1. Create and protect the `release-candidate` environment, restrict it to release tags, and configure the real required-reviewer path. Naming the environment in workflow YAML does not configure those protections by itself.
2. Protect `master` with the required CI checks and a reviewed emergency-bypass policy.
3. Enable private vulnerability reporting, update the Security contact link to the private advisory form, and test it before announcing the beta.
4. Enable immutable releases and confirm the setting through a read-only query before publication.

Do not push a public release tag merely to test these controls; exercise them first with the repository's documented candidate procedure.

## Conduct and licensing

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Contributions are accepted under the [MIT License](LICENSE). Maintainers may close contributions that cannot be verified safely, disclose sensitive data, or exceed the documented product scope.
