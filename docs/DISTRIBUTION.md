# Distribution

Last updated: 2026-07-18

Desk Setup Switcher has no public release. The repository can currently build and inspect an ad-hoc-signed development DMG, but that artifact is not an end-user distribution. The official `v0.1.0` public beta requires Developer ID signing, hardened runtime, secure timestamps, notarization, stapling, Gatekeeper verification, protected approval, and clean-download evidence before publication.

## Distribution classes

| Class | Purpose | May be public/canonical? |
| --- | --- | --- |
| Local or CI ad-hoc DMG | Contributor testing, deterministic package inspection, and historical evidence | No |
| GitHub unsigned draft prerelease | A protected review record for the current verification pipeline | No |
| Developer ID + notarized release candidate | Clean-install beta testing after all trust checks pass | Only inside a protected draft until final approval |
| Approved `v0.1.0` GitHub Release | Canonical public-beta download with checksum, provenance, SBOM, and release evidence | Yes |
| Homebrew cask | Convenience installation after the canonical notarized release is proven | Only after the GitHub Release; own tap first |

An ad-hoc signature is never promoted by changing its description. A public artifact must be built through the separate identity-signed path and must pass every public gate below.

## Current development baseline

The 2026-07-18 open-source baseline's no-Developer-ID path passed 496 checks: 173 XCTest checks, 322 Swift Testing checks across 40 suites, and one isolated native `NSPopover` regression. Universal Debug/Release, Analyze, project-generation verification, DMG creation, SHA-256 validation, mounted metadata/resources, `arm64 x86_64`, and ad-hoc signature classification passed. The package was not installed or launched.

- Development-only DMG SHA-256: `961f4044996c0f5fc0b4e8e782355da4d620c553e4c1891918d19323f6d67eac`
- Authoritative record: [Open-source release baseline audit](OPEN-SOURCE-RELEASE-BASELINE-2026-07-18.md)

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

## Current GitHub Actions candidate path

The CI workflow uses a complete checkout, runs `make verify` and `make audit-public-release`, and uploads the ad-hoc DMG/checksum for 14 days. It does not receive signing or notarization secrets.

The tag workflow currently:

1. triggers for `v*` tags and requires the tag to equal `v` plus `CFBundleShortVersionString`;
2. references the GitHub environment named `release`;
3. reruns `make verify` and `make audit-public-release` from a complete checkout; and
4. calls `gh release create` with `--draft --prerelease`, an **unsigned candidate** title, and only the ad-hoc DMG/checksum.

It does not use Developer ID, hardened runtime, secure timestamping, notarization, stapling, SBOM generation, artifact attestation, clean-install verification, or an automatic publish command. A draft/prerelease is not a public release, and the current workflow must never be described as the official distribution path.

Do not push the final `v0.1.0` tag until the release-only signed path exists and the release environment is actually protected. The workflow name `environment: release` does not configure protection by itself. A read-only GitHub API check on 2026-07-18 found zero configured environments and no protection on `master`.

Before any release tag is allowed, a repository administrator must:

- create the `release` environment;
- restrict it to intended release tags;
- configure the real required reviewer and decide whether self-review and administrator bypass are prohibited;
- store signing/notarization credentials only in that protected environment;
- protect `master` with the required CI checks and a documented emergency-bypass policy; and
- enable the private reporting path required by [SECURITY.md](../SECURITY.md).

See [GOVERNANCE.md](../GOVERNANCE.md) for current roles and approval authority. GitHub documents that environment secrets remain unavailable until required approval when that protection is configured; merely referencing an environment supplies no such guarantee.

## Required public-beta trust path

This path is mandatory for `v0.1.0` and is not implemented yet. The operator must use one release build as the candidate through signing, packaging, notarization, stapling, and approval. A retry after any source, resource, entitlement, or executable change is a new candidate and must restart the gate.

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

codesign --verify --deep --strict --verbose=2 "Desk Setup Switcher.app"
codesign --display --verbose=4 "Desk Setup Switcher.app"
codesign --display --entitlements - "Desk Setup Switcher.app"
```

If the audited app needs entitlements, the implemented script must add `--entitlements` with the reviewed release plist; it must not reuse debug entitlements implicitly. The release script must supply `--options runtime` and `--timestamp` when signing. It must inspect the authority chain and fail if the identity, Team ID, hardened-runtime flag, secure timestamp, or reviewed entitlement set differs from policy. Ad-hoc signing, Apple Development, and Mac App Distribution identities are not substitutes for Developer ID Application.

Package that exact signed app without rebuilding it. Sign the final DMG with the reviewed Developer ID identity and a secure timestamp, then verify the app extracted from the DMG is byte-identical to the signed app that entered packaging:

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
- GitHub artifact provenance/attestation bound to the exact final asset; and
- tag, commit, workflow run, source tree, and artifact identity.

Attach the signed/stapled DMG, checksum, SBOM, provenance/attestation, curated English/Korean notes, and sanitized evidence to a protected draft. The repository currently has no SBOM, attestation, or signed-release implementation, so none may be claimed yet.

Download every proposed asset back through GitHub, recompute its hash, verify its signature and attestation, and compare it with the approved local candidate. Enable immutable-release behavior when available and compatible with the repository plan. Approval must be recorded before publication; no workflow may silently turn the current unsigned draft into a public release.

## Clean-download public-beta gate

Test the exact downloaded and quarantined candidate on a clean account or Mac without deleting quarantine metadata:

1. Verify the published checksum before mounting.
2. Confirm Gatekeeper identifies the Developer ID publisher and opens the app without an **Open Anyway** workaround.
3. Verify first launch, menu-bar-only behavior, Capture → Edit → Review & Apply explanation, permissions, and login-at-launch default-off/explicit opt-in.
4. Verify upgrade, schema migration, last-known-good backup recovery, import/export, diagnostics, uninstall, and optional local-data removal.
5. Record Apple Silicon results. Do not advertise Intel until the physical Intel matrix passes.
6. Collect at least three external clean-install beta results and resolve every P0/P1 issue before public approval.

No live display, audio, or network mutation is authorized by this distribution procedure. Hardware mutation evidence requires its own explicit approval, preflight snapshot, interactive action, and rollback procedure from the [support matrix](SUPPORT-MATRIX.md). Features without that evidence remain labelled mock verified, live-read verified, experimental, or unverified.

Keyboard operation, accessibility names/values, and non-color cues remain release requirements. Full-app VoiceOver certification is not a release gate and must not be claimed.

## Homebrew sequence

GitHub Releases remains the canonical download. Do not create or advertise a cask until the Developer ID-signed, notarized, stapled public artifact has a stable GitHub Release URL and final SHA-256.

After that release:

1. Add a cask to a project-owned tap using the canonical versioned URL and exact checksum.
2. Define uninstall and `zap` behavior that accurately covers the app bundle and optional app-owned local data without deleting unrelated files.
3. Verify clean `install`, `upgrade`, `uninstall`, and `zap` on supported macOS/Apple Silicon using the downloaded notarized artifact.
4. Keep the official Homebrew Cask submission as a later milestone after the self-hosted tap and patch-release process are proven.

Homebrew must not become a runtime dependency, and the app must not gain an updater or outbound network path.

## Release failure and support policy

Never replace a published asset or move/reuse its tag to hide a problem. Mark the affected release as discontinued or affected, stop promotion/download links, and publish a corrected patch version through the full gate. The latest beta is supported; the immediately preceding beta may receive critical fixes for up to 30 days when practical. The stable support window is the latest and immediately preceding stable minor lines, as defined in [Compatibility and versioning](COMPATIBILITY.md).

## Final release evidence checklist

For each public release, record:

- tag, commit, app version, build number, clean-worktree status, and protected approval;
- Xcode, Swift, SDK, runner macOS, supported CPU, and deployment target;
- `make verify`, `make audit-public-release`, `git diff --check`, remote CI, and version/tag checks;
- exact build/sign/package candidate lineage with no rebuild between stages;
- Developer ID authority/Team ID, hardened runtime, secure timestamps, and reviewed entitlements;
- notary submission ID, accepted status, redacted log, stapling, and app/DMG Gatekeeper assessments;
- mounted package resources, checksum, SBOM, provenance/attestation, and re-downloaded asset identity;
- clean-quarantine first launch, upgrade, migration/backup recovery, import/export, diagnostics, uninstall, and local-data removal;
- external beta results and zero unresolved P0/P1 issues;
- capability claims matched to the support matrix, with no Intel, hardware-mutation, or VoiceOver certification overclaim;
- GitHub Release URL plus synchronized site, README, English/Korean notes, and support/security documents; and
- Homebrew status, explicitly “not offered” until post-notarization verification.

Do not include personal device identifiers, real SSIDs, exact locations, IP host addresses, credentials, or unredacted diagnostics in release evidence.

## Authoritative references

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [GitHub: Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub: Using artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations)
- [Homebrew: Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
