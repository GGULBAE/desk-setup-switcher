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

## Releases

Release preparation follows [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). The release operator must use the protected release environment and prepare a draft from one immutable candidate. The release approver verifies the tag/commit/version, CI, signature/notarization/stapling, checksums, provenance, SBOM, support claims, and clean-quarantine evidence before publication.

The current tag workflow uses the named `release` environment, reruns the repository gates and public-history audit, and creates only an **unsigned draft prerelease candidate**. It is not a Developer ID signing, notarization, promotion, or publication path. A separate reviewed path must be implemented and proven before a draft can become the canonical public download.

The repository currently has one maintainer, so independent two-person approval is not claimed. Before the first public beta, the repository administrator must configure the protected release environment and document the actual approver path. A bad public release is marked as affected or withdrawn; its tag and assets are not overwritten. Recovery uses a new patch version.

### Repository settings still required

A read-only GitHub API check on 2026-07-18 found no configured repository environments, no protection on `master`, disabled Discussions, and disabled private vulnerability reporting. The support issue form is the deliberate alternative to Discussions, but the other controls remain public-launch blockers:

1. Create and protect the `release` environment, restrict it to release tags, and configure the real required-reviewer path. Naming the environment in workflow YAML does not configure those protections by itself.
2. Protect `master` with the required CI checks and a reviewed emergency-bypass policy.
3. Enable private vulnerability reporting, update the Security contact link to the private advisory form, and test it before announcing the beta.

Do not push a public release tag merely to test these controls; exercise them first with the repository's documented candidate procedure.

## Conduct and licensing

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Contributions are accepted under the [MIT License](LICENSE). Maintainers may close contributions that cannot be verified safely, disclose sensitive data, or exceed the documented product scope.
