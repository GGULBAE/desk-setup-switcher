# Release incident and patch runbook

Use this runbook when a published release is affected by a P0/P1, signing/notarization or attestation failure, unsafe behavior, privacy/security problem, data-loss risk, or a misleading support claim. It does not authorize disclosure of confidential reports or live system mutation.

The governing rule is simple: **never replace an asset, move/reuse a tag, or rewrite provenance to hide a problem**. Preserve evidence and recover with a new patch version through the full [distribution gate](DISTRIBUTION.md).

## 1. Classify and stop

1. The triager records sanitized impact and proposes severity. The maintainer decides public product severity; the security responder decides confidential security severity.
2. A P0 stops testing, publication, and promotion immediately. A P1 blocks the affected release and any pending promotion until resolved.
3. Keep confidential details in the private security channel. The public record contains only the minimum safe status and recovery guidance.
4. Record the affected version, tag, build number, commit, final DMG SHA-256, all three attestation bundles, first known report time, decision time, and decision owner in the release evidence record.

## 2. Contain without destroying evidence

- Mark the GitHub Release title and opening note as **Affected — do not install** or **Discontinued**.
- Keep the immutable tag, exact nine-asset set, checksum, SBOM, all three attestation bundles, and release evidence intact. Do not delete or replace them.
- Remove the affected version from the site/README primary download path and replace it with a clear affected-release notice. Do not silently redirect the same version to different bytes.
- Stop scheduled or pending promotional posts. Correct already-published posts with a direct affected-release notice where the surface permits.
- If a safe non-affected predecessor exists, identify it explicitly by its original canonical URL and hash. Do not call it supported until its compatibility and security status are rechecked.
- If no safe supported version exists, state that no supported download is currently available.

Immutable releases are required for this repository. Publication-time immutability is not relaxed during an incident; only title/notes and surrounding project links may be updated as the platform permits.

## 3. Investigate and choose recovery

1. Preserve sanitized diagnostics and exact candidate lineage. Do not ask a reporter to reproduce an unsafe mutation merely to improve evidence.
2. Determine whether the issue affects source, signing, notarization, packaging, migration, install/uninstall, support claims, or external infrastructure.
3. If any app byte, resource, entitlement, version, build number, package, or provenance subject changes, create a new candidate.
4. Use the next patch version and a new monotonically increasing build number. Never reuse the affected tag.
5. Record whether a private advisory, credential rotation, support-matrix downgrade, data-recovery guidance, or public disclosure is required.

## 4. Build and verify the patch

- Start from a clean reviewed commit.
- Add deterministic regression coverage where possible without live mutation.
- Repeat the complete [release evidence template](RELEASE-EVIDENCE-TEMPLATE.md): local and remote gates, one-candidate signing, notarization, stapling, Gatekeeper, checksum, SBOM, all three subject-specific attestation bundles, exact nine-asset redownload, clean lifecycle, and external beta.
- Resolve every P0/P1 against the new candidate. Re-labelling or closing without evidence is insufficient.
- Obtain the security-responder no-confidential-blocker sign-off and explicit maintainer approval again.

## 5. Publish and communicate

1. Publish the new patch as a separate immutable tag and asset set.
2. Keep the affected release marked and linked to the patch notes; do not erase the incident history.
3. Update the canonical site, README, support matrix, SECURITY support table, changelog, release ledger, English/Korean notices, and checksums together.
4. Re-download all nine patch assets and verify byte identity, the final DMG SHA-256/signature, and all three attestation bundles.
5. Resume promotion only after the maintainer explicitly approves each channel.

## 6. Close and review

- Record containment time, patch publication time, affected scope, recovery status, and remaining support work without personal or confidential details.
- Verify that the latest non-affected beta is the support target and that any preceding-beta critical-fix window is stated accurately.
- Check the site and release links from a clean browser session.
- Update this runbook when the response exposed a missing control, but never rewrite the historical incident record.
