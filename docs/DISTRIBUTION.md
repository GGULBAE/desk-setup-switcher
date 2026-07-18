# Distribution

Last updated: 2026-07-18

Desk Setup Switcher has no public release. The repository can currently build and inspect an ad-hoc-signed development DMG, but that artifact is not an end-user distribution. The official `v0.1.0` public beta requires Developer ID signing, hardened runtime, secure timestamps, notarization, stapling, Gatekeeper verification, protected approval, and clean-download evidence before publication.

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

The current 2026-07-18 public-surface candidate's no-Developer-ID path passed 1,648 deterministic checks/assertions: 501 app checks (178 XCTest cases, 322 default Swift Testing cases across 39 suites, and one isolated native `NSPopover` case in a 40th Swift Testing suite) plus 1,147 release-tooling assertions (328 base release-policy, 659 remote-controls policy/normalizer, 79 collector-wrapper mock, and 81 shell guard assertions). Universal Debug/Release, Analyze, project-generation verification, DMG creation, SHA-256 validation, mounted metadata/resources, `arm64 x86_64`, and ad-hoc signature classification passed. The release-tooling evidence is simulated and structural, not a credentialed signing or notarization result. The package was not installed or launched.

- Current development-only DMG SHA-256: `d77435ee46cdc69f39f9ace41f74e6c2b63830eda0123b4a10818aa6516e5b96`
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

- `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg`
- `artifacts/Desk-Setup-Switcher-0.1.0-unsigned.dmg.sha256`

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
shasum -a 256 -c Desk-Setup-Switcher-0.1.0-unsigned.dmg.sha256
```

macOS may require an explicit **Open Anyway** decision for this development artifact. Never disable Gatekeeper globally or remove quarantine recursively. End-user documentation, the demo site, and promotional material must not link to this artifact or instruct ordinary users to bypass Gatekeeper.

## Proposed local workflow and effective remote path

The local workspace's proposed CI workflow uses a complete checkout, runs `make verify` and `make audit-public-release`, and uploads the ad-hoc DMG/checksum for 14 days. It does not receive signing or notarization secrets.

The local workspace now proposes a separate signed-candidate workflow:

1. it runs only through manual `workflow_dispatch` on the existing `v0.1.0` tag ref and requires the exact expected commit plus a typed confirmation;
2. it references the protected environment named `release-candidate`, with job-scoped contents/identity/attestation permissions and protected signing/notarization values;
3. it reruns preflight, `make verify`, and the public-history audit from a complete tag checkout on a GitHub-hosted runner, then builds once, signs, notarizes, staples, assesses, checksums, and records the candidate;
4. it creates an SBOM plus separate DMG-provenance, DMG-SBOM, and release-manifest-provenance attestations; creates only a draft prerelease with curated English/Korean notes and the exact nine-asset set; downloads all nine assets again; and verifies identity and all three bundles; and
5. it retains the same final candidate as a workflow artifact for the browser-download external beta path and contains no public-release publication command.

This workflow and its release scripts are unproven local tooling. They have not run with Developer ID/notarization credentials, have not produced a signed candidate, and have not been pushed. A draft/prerelease is not a public release, and source inspection cannot substitute for protected environment configuration or an actual accepted run.

The release scripts fail closed on self-hosted runners. Each protected secret is scoped to its one consuming workflow step, which directly replaces the runner shell with `/bin/bash`; the script copies the value into a non-exported variable and unsets the original before `source`, `dirname`, or any other child process can run. The certificate, ephemeral Keychain, and notary key use private randomized paths below `RUNNER_TEMP`; only their non-secret path names cross steps through GitHub's `GITHUB_ENV` file. The decoded certificate is deleted immediately after import, the Keychain as soon as app and DMG signing finish, and the notary key immediately after the accepted submission log is fetched, with absence checked after every normal deletion. Catchable `INT`/`TERM` targets the tracked notarization process group, grants a short `TERM` window, then escalates to `KILL` before status-preserving cleanup; `SIGKILL` delivered to the runner shell itself, host loss, and power loss cannot be handled by a shell trap and therefore retain the GitHub-hosted ephemeral runner and `RUNNER_TEMP` teardown as the last boundary. Apple's `security import` still requires the certificate passphrase as a quoted `-P` process argument for that brief isolated command; it is never logged or inherited through the child environment.

Strict duplicate-key-free JSON validation emits the normalized submission ID from the same verified in-memory snapshot rather than reopening the raw result. JSON and text sanitization replace the longest, most-specific repository/home/runner path first, then the sanitized result and log are semantically rebound to the submission, archive, and hashes. The always-cleanup path is idempotent, never follows a signing-path symlink, and refuses malformed, escaped, or unexpected signing paths. Deterministic mock lifecycle tests exercise successful and failed import, `GITHUB_ENV` handoff, idempotent follow-up cleanup, symlink refusal, secret-environment isolation, and prompt process-group cleanup even when the child ignores `TERM`; this remains simulated evidence, not a credentialed signing/notarization run.

The effective remote workflow on `origin/master` is older and unsafe for a release tag. A read-only inspection on 2026-07-18 found that it triggers on `v*`, receives `contents: write`, builds an unsigned DMG, and calls `gh release create` without `--draft`, `--prerelease`, or an environment. The current local protection changes have not been pushed. Therefore **no `v*` tag may be pushed** until the safe workflow is merged, remote protections are configured, and a read-only check proves that the unsafe path is no longer effective.

Do not push the final `v0.1.0` tag until the release-only signed path is merged and the `release-candidate` environment is actually protected. Referencing an environment in workflow YAML does not configure protection by itself. A read-only GitHub API check on 2026-07-18 found zero configured environments and no protection on `master`.

The detailed [remote release controls audit](REMOTE-RELEASE-CONTROLS-AUDIT-2026-07-18.md) additionally records zero branch/tag rulesets, disabled immutable releases and private vulnerability reporting, empty repository secret/variable name lists, the missing protected environment, the pending sole-maintainer reviewer-policy decision, stale repository metadata, and the exact containment → feature-branch → PR → read-back sequence. It inspected no credential value. That audit authorizes no remote mutation; it exists so approval can name a bounded operation and rollback path.

`make verify-remote-controls` is the explicit final-pre-tag read-only gate; it is intentionally excluded from ordinary `make verify` because credentials and network state are not deterministic test inputs. Its checked-in policy is fail-closed and currently `configured:false`, so the command stops before resolving `gh` or making a GitHub request. Once completely configured, the wrapper performs local reads and authenticated GitHub GETs, projects variable responses to names before evidence is written, binds both the release and CI workflow blobs, and rejects missing admin visibility or drift. It cross-binds the required check to the pinned CI workflow's exact successful run and job, then repeats every release-critical remote observation and requires normalized equality before success. Only secret/variable names are emitted, persisted, normalized, compared, or recorded; no credential value is inspected by the operator or retained in evidence. A successful result deliberately reports `manual_gates=1`: GitHub's documented REST response does not prove the environment's administrator-bypass setting, so that setting requires separate read-only Settings evidence. Calling `scripts/release/remote_controls_policy.rb` directly with a normalized evidence fixture exercises only the offline policy component; it is not the final remote gate and must not be recorded as one.

Configure the authoritative policy through a reviewed code change, not by copying the synthetic fixture. Populate every closed-schema field from reviewed read-only evidence: repository numeric and node identity plus approved metadata/state, release version/tag, release and CI workflow IDs/names/paths/blobs, exact CI check identity, operator and reviewer IDs/logins/types, and approval mode/count/self-review behavior. Review that diff, commit the policy together with both workflow blobs it names, merge it through the protected `master` path, and wait for exact-commit CI. The final command must then run from a clean, complete, non-shallow checkout whose HEAD is the effective remote `master`, authenticated as the configured operator with repository-admin visibility, while no `v*` ref or GitHub Release exists. Capture its sanitized transcript immediately before separately approving tag creation; the verifier configures nothing, pushes nothing, and does not itself authorize a tag.

Before any release tag is allowed, a repository administrator must:

- create the `release-candidate` environment and restrict it to the exact `v0.1.0` tag;
- configure the real required reviewer and self-review behavior, then separately record the environment administrator-bypass setting from the Settings UI;
- store only the exact signing/notarization credential names in that protected environment and prove the repository level does not shadow them;
- protect `master` with the exact required CI/review rules and no standing bypass actor; emergency recovery is a separately approved ruleset change or disable;
- use one `v*` creation ruleset with only the approved release-operator User as bypass and a separate no-bypass `v*` update/deletion ruleset, so tag creation authority never becomes tag-move or tag-delete authority;
- require selected GitHub-owned Actions, full-SHA pinning, read-only default workflow tokens, and no workflow PR-review approval permission;
- enable immutable Releases and the private reporting path required by [SECURITY.md](../SECURITY.md);
- create `needs-triage`, apply the exact approved public repository metadata and disabled-Discussions state; and
- merge the anchored policy/workflows, pass exact-commit CI, and keep both `v*` refs and Releases empty until the final-pre-tag check succeeds.

See [GOVERNANCE.md](../GOVERNANCE.md) for current roles and approval authority. GitHub documents that environment secrets remain unavailable until required approval when that protection is configured; merely referencing an environment supplies no such guarantee.

## Required public-beta trust path

This path is mandatory for `v0.1.0`. Proposed local workflow and helper tooling now implement its shape, but they are unpushed, unconfigured, and unproven with release credentials; no signed candidate exists yet. The operator must use one release build as the candidate through signing, packaging, notarization, stapling, external beta, and approval. A retry after any source, resource, entitlement, or executable change is a new candidate and must restart the gate.

“Same candidate” means the source commit, tag, app version, build number, signed executable bytes, architecture-labelled `arm64` and `x86_64` CodeDirectory hashes, designated requirement, entitlements, resources, and supported architecture set do not change after the release build. Packaging, notarization, and stapling legitimately change the DMG bytes, so the evidence record must retain the pre-notarization DMG hash and the final post-staple DMG hash rather than claiming those two containers are byte-identical. The app mounted from the final DMG must match the recorded signed app identity and resource manifest. All tester reports, the final checksum, SBOM, three attestation bundles, draft assets, and re-downloaded public asset must bind to their exact recorded subjects and the final post-staple DMG SHA-256 where applicable. Any rebuild or app-bundle change creates a new build number and invalidates earlier lifecycle and beta reports.

### 1. Freeze and audit the candidate

- Start from a clean commit whose app version, build number, tag, changelog, support matrix, and completion ledger agree.
- Run `make verify`, `make audit-public-release`, and `git diff --check` from a complete checkout.
- Confirm the supported public-beta platform is Apple Silicon unless physical Intel verification has been recorded.
- Audit the minimum entitlements. Hardened-runtime exceptions require an explicit justification; `com.apple.security.get-task-allow` must not be present in the release signature.
- Confirm the Apple Developer Program team, Developer ID Application certificate, and notarization credential are available without exporting or logging secrets.

### 2. Build once and sign for distribution

Build the release app once. Sign nested code from the inside out if any is introduced, then sign the app with a **Developer ID Application** identity, hardened runtime, and secure timestamp. Illustrative verification commands are:

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

Package that exact signed app without rebuilding it. Sign the final DMG with the reviewed Developer ID identity and a secure timestamp, then verify that the mounted app preserves the signed executable hash, both architecture-labelled CodeDirectory hashes, designated requirement, entitlements, and recorded resource manifest of the app that entered packaging:

```sh
codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
  --timestamp \
  "Desk-Setup-Switcher-0.1.0.dmg"
codesign --verify --strict --verbose=2 "Desk-Setup-Switcher-0.1.0.dmg"
```

### 3. Notarize, staple, and assess

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

The implementation must parse the submission result and require `Accepted`; command exit alone is insufficient. Preserve the submission ID and redacted notary log as release evidence. Staple and validate the final DMG, mount it read-only, and assess the contained app separately with `spctl --assess --type execute --verbose=4`. Any modification after signing or notarization invalidates the candidate and restarts the path.

### 4. Verify and attach release evidence

After stapling, compute the final SHA-256 and verify:

- Developer ID authority, Team ID, hardened runtime, secure timestamps, and minimal entitlements;
- notarization result/log and stapler validation;
- Gatekeeper assessment of both DMG and app;
- deployment target, `arm64` support, resources, localization, bundle ID, app/build versions, and login-item opt-in behavior;
- checksum file syntax and recomputation;
- an SBOM for the exact candidate;
- three separate GitHub attestation bundles: final-DMG provenance, final-DMG SPDX 2.3 SBOM, and release-manifest provenance, each bound to its exact subject; and
- tag, commit, workflow run, source tree, and artifact identity.

Attach exactly nine assets to the protected draft: the signed/stapled DMG, checksum, SPDX JSON, release manifest, sanitized notary result, sanitized notary log, DMG provenance bundle, DMG SBOM bundle, and release-manifest provenance bundle. Curated English/Korean notes are the Release body, not an asset. The local workspace contains proposed SBOM, attestation, and signed-release tooling, but it has not run with protected credentials or produced an accepted candidate; none of those outputs may be claimed yet.

Download all nine assets back through GitHub, require that no extra or missing asset exists, compare each byte-for-byte with the approved local candidate, recompute hashes, verify signatures, and verify all three attestation bundles. GitHub immutable releases are available to this repository and must be enabled before publication; the approval record must include a read-only confirmation of that setting. Approval must be recorded before publication, and no workflow may turn an unsigned artifact or a protected draft into a public release without that recorded approval.

## Clean-download public-beta gate

Test the exact downloaded and quarantined candidate on a clean account or Mac without deleting or manufacturing quarantine metadata. Use [the release evidence template](RELEASE-EVIDENCE-TEMPLATE.md) for the lifecycle record and [the external beta template](EXTERNAL-BETA-REPORT-TEMPLATE.md) for each tester.

The three external testers must obtain the final stapled DMG from the protected workflow artifact produced by the approved run. They must download the artifact archive through a normal browser, extract the DMG through the normal macOS path, and record the actual `com.apple.quarantine` value on the extracted DMG before opening it. A report does not count when that attribute is absent, was manually added, or was deleted. Testers need read access to the public repository and artifact, not push, release, environment, or secret access. Each report must verify the identical final DMG SHA-256 and the final-DMG provenance attestation bound to the protected workflow run.

The lifecycle gate is itemized; one successful first launch cannot stand in for the other rows:

1. Verify the published checksum before mounting.
2. Confirm Gatekeeper identifies the Developer ID publisher and opens the app without an **Open Anyway** workaround.
3. Verify first launch, menu-bar-only behavior, Capture → Edit → Review & Apply explanation, permissions, and launch-at-login default-off/explicit opt-in.
4. Verify an upgrade from the recorded predecessor build preserves current schema-1 profiles, settings, selection, backups, and the login-item consent boundary. Record both build numbers and hashes.
5. Verify a synthetic schema-0 document migrates to schema 1, remains semantically valid, and preserves a recoverable last-known-good backup without applying a system setting.
6. With the app closed and only synthetic data present, exercise primary-file corruption and verify last-known-good backup recovery, quarantine behavior, and a clean relaunch. Do not upload raw profiles or diagnostics.
7. Verify import replacement/no-overwrite export, diagnostics browse/refresh/clear, and denial isolation with redacted or synthetic values.
8. Verify uninstall after disabling the optional login item, then separately verify optional removal of the app-owned Application Support data and preferences. Confirm exported files outside app storage are not silently deleted.
9. Record Apple Silicon and macOS results. Do not advertise Intel until the physical Intel matrix passes.
10. Collect at least three external clean-install beta results for the identical candidate and obtain the release-blocker sign-offs below before public approval.

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

Never replace a published asset or move/reuse its tag to hide a problem. Mark the affected release as discontinued or affected, stop promotion/download links, and publish a corrected patch version through the full gate. Follow the [release incident runbook](RELEASE-INCIDENT-RUNBOOK.md), preserving the affected tag, all nine assets, hashes, and all three attestation bundles as evidence. The latest non-affected beta is the support target; the immediately preceding beta may receive critical fixes for up to 30 days when practical. The stable support window is the latest and immediately preceding stable minor lines, as defined in [Compatibility and versioning](COMPATIBILITY.md).

## Final release evidence checklist

For each public release, complete [the release evidence template](RELEASE-EVIDENCE-TEMPLATE.md) as the protected approval record and keep the curated English/Korean notes under [`docs/releases/`](releases/). Release notes are not evidence. At minimum, record:

- tag, commit, app version, build number, clean-worktree status, and protected approval;
- Xcode, Swift, SDK, runner macOS, supported CPU, and deployment target;
- `make verify`, `make audit-public-release`, `git diff --check`, remote CI, and version/tag checks;
- exact build/sign/package candidate lineage with no rebuild between stages;
- Developer ID authority/Team ID, hardened runtime, secure timestamps, and reviewed entitlements;
- notary submission ID, accepted status, redacted log, stapling, and app/DMG Gatekeeper assessments;
- mounted package resources, checksum, SBOM, the three subject-specific attestation bundles, and exact nine-asset re-download identity;
- browser-download and extracted-DMG quarantine evidence, clean first launch, login default-off, upgrade, schema migration, backup recovery, import/export, diagnostics, uninstall, and optional local-data removal as separate results;
- three external beta reports bound to the identical final DMG SHA-256 and final-DMG provenance attestation, zero public P0/P1 issues, and confidential security-responder zero-blocker sign-off;
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
