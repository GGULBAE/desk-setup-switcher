# Distribution

Last updated: 2026-08-05

Desk Setup Switcher uses a cost-free public-beta distribution path. The initial
release is published from GitHub Releases without the Mac App Store, paid Apple
Developer Program membership, Developer ID signing, or Apple notarization.

There is no supported public download yet. Until the exact `v0.1.0` release
gate below passes and a maintainer publishes its GitHub Release, local builds
and ordinary CI artifacts remain development evidence only.

## What “unsigned” means here

The project calls the public package **unsigned** because it has no Developer ID
identity and no Apple notarization ticket. The app bundle still receives a free
ad-hoc code-integrity signature because `SMAppService` and macOS bundle integrity
require a valid signature. That signature does not authenticate the publisher.

Consequences for users:

- macOS is expected to block the first launch as an unidentified developer;
- users must verify the canonical GitHub Release URL and SHA-256 checksum;
- users then make one explicit **System Settings → Privacy & Security → Open
  Anyway** decision for that version;
- documentation must never tell users to disable Gatekeeper globally, remove
  quarantine with `xattr`, or ignore a checksum mismatch; and
- a damage warning or mismatched checksum is a stop condition, not an expected
  unsigned-release warning.

## Distribution classes

| Class | Purpose | Supported public download? |
| --- | --- | --- |
| Local `make package` DMG | Contributor development and deterministic package inspection | No |
| Ordinary CI artifact | Review of a specific commit; expires and is not canonical | No |
| Draft GitHub Release | Maintainer review of the exact tag, DMG, checksum, and notes | No |
| Maintainer-published versioned GitHub Release | Canonical unsigned public beta after every required gate passes | Yes |
| Third-party mirror or repack | Outside the project trust boundary | No |
| App Store, Homebrew, Developer ID/notarized package | Not part of the initial free beta | No initial support |

Changing a label does not promote an artifact. Only the exact DMG bytes whose
checksum is attached to the maintainer-approved versioned GitHub Release become
supported.

## Build and package

The current packaging command is:

```sh
make verify
make audit-public-release
```

`make verify` builds universal `arm64 x86_64` Debug and Release configurations,
runs the deterministic app and release-tooling tests, analyzes the project,
creates the versioned DMG and checksum, mounts the image read-only, verifies
bundle metadata and English/Korean resources, and requires the expected ad-hoc
signature with no identity authority.

For version `VERSION`, packaging creates:

```text
artifacts/Desk-Setup-Switcher-VERSION-unsigned.dmg
artifacts/Desk-Setup-Switcher-VERSION-unsigned.dmg.sha256
```

DMGs are not byte-for-byte reproducible. Every release attempt therefore uses
the checksum generated beside that exact DMG; a checksum from a local or older
CI package must never be copied into release notes.

## Manual-only GitHub Release preparation

`.github/workflows/unsigned-release.yml` is the free release-preparation path.
It is manual-only and accepts one existing annotated `v*` tag, its exact commit,
and a typed confirmation. It:

1. checks out the existing tag with complete history;
2. binds the tag, checkout, bundle version, and expected commit;
3. runs `make verify`, `make audit-public-release`, and the public-surface gate;
4. verifies the exact unsigned DMG and checksum inventory;
5. uploads the pair as a retained Actions artifact; and
6. creates a **draft prerelease** with the checked-in bilingual release notes.

The workflow does not publish a Release, create or move a tag, overwrite an
existing asset, use Apple credentials, disable Gatekeeper, deploy the site, or
perform a live display/audio/network/input mutation. A maintainer must inspect
the draft and publish it through a separate explicit GitHub action.

If the tag or Release already exists in a conflicting state, preparation stops.
Do not delete, overwrite, or silently repair an ambiguous public release; follow
the [release incident runbook](RELEASE-INCIDENT-RUNBOOK.md).

## Required `v0.1.0` public-beta gate

All of the following are required before the draft becomes public:

- [ ] The release commit is clean, reviewed, merged to the default branch, and
      identified by one annotated `v0.1.0` tag that matches bundle version
      `0.1.0`.
- [ ] `make verify`, `make audit-public-release`,
      `make verify-public-surface`, and `git diff --check` pass for that exact
      commit.
- [ ] The workflow-produced DMG and checksum pass checksum, mount, bundle,
      localization, exact architecture, per-slice minimum-OS, and ad-hoc/no-
      Developer-ID classification checks.
- [ ] The GitHub draft contains only the intended versioned DMG, checksum, and
      reviewed bilingual notes; no local or ordinary CI artifact is substituted.
- [ ] The release notes and public pages say clearly that the app is Developer
      ID-unsigned and not notarized, and explain SHA-256 plus the one-time
      **Open Anyway** path.
- [ ] At least one exact-candidate lifecycle pass succeeds on Apple Silicon and
      macOS 14 Sonoma before macOS 14 becomes a support claim. It covers browser
      download, checksum, Finder copy to `/Applications`, first blocked launch,
      **Open Anyway**, menu-bar launch, launch-at-login default-off, profile
      creation with synthetic labels, upgrade/migration/backup recovery,
      import/export, diagnostics, uninstall, and optional local-data removal.
- [ ] The lifecycle pass confirms the DMG was ejected before launch and records
      the exact installed bundle version/build and executable digest.
- [ ] No P0 or P1 product, privacy, security, rollback, or installation blocker
      remains open.
- [ ] GitHub private vulnerability reporting is enabled and the documented
      private route works before public announcement.
- [ ] A maintainer gives explicit final approval, publishes the draft, verifies
      the public DMG and checksum by fresh download, and only then switches the
      tracked site/public-copy state from `holding` to `published`.

Hardware mutation is not required for the initial beta and must not be inferred
from mock verification. Any optional live mutation evidence remains separately
authorized, interactive, snapshot-bound, and rollback-documented.

## User installation contract

Published instructions use only this sequence:

1. Open the exact versioned GitHub Release.
2. Download its `-unsigned.dmg` and `.sha256` file.
3. Verify SHA-256 before opening the image.
4. Drag the app to **Applications** and eject the DMG.
5. Try to open the app once and observe the expected unidentified-developer
   block.
6. Reconfirm the URL and checksum, then use **System Settings → Privacy &
   Security → Open Anyway** once.
7. Stop if macOS reports damage or if any checksum, version, build, or URL does
   not match.

The project does not provide an in-app updater. Users obtain later versions from
the same canonical Releases page and may need to repeat the one-time trust
decision for each new unsigned version.

## Optional future paid path

Developer ID signing and notarization may be reconsidered if installation
friction becomes a material adoption or support problem. It is not a `v0.1.0`
gate and App Store distribution remains out of scope. Historical signed-
candidate policy and mock tooling in `scripts/release/` are retained as audited
engineering history; they do not describe the active free release path and
must not consume credentials or publish a Release unless a later explicit
decision reactivates them.

## Homebrew

Homebrew is not offered for the initial beta. An unsigned cask would not remove
the Gatekeeper trust decision and could obscure the canonical checksum path.
Any future project-owned tap requires separate install, upgrade, uninstall, and
`zap` verification and must continue to identify the unsigned/notarization
boundary honestly.

## Authoritative references

- [Completion criteria and evidence ledger](COMPLETION-CRITERIA.md)
- [Support matrix](SUPPORT-MATRIX.md)
- [Bilingual `v0.1.0` release notes](releases/v0.1.0.md)
- [Security policy](../SECURITY.md)
- [Release incident runbook](RELEASE-INCIDENT-RUNBOOK.md)
- [Release asset provenance](RELEASE-ASSET-PROVENANCE.md)
