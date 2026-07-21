# External clean-install beta report template

Use one copy per external tester as the human worksheet. A report counts toward the three-report public-beta gate only when its matching closed JSON report passes the machine validator and every mandatory row passes for the identical final stapled DMG. At least one of the three accepted reports must cover the full lifecycle on Apple Silicon/macOS 14 Sonoma; selecting a macOS 14.0 deployment target is not runtime evidence. The tester must not be the release operator or release approver and must not have repository push, release, environment, or secret access.

Do not include a personal name, account name, home path, serial number, device UID, real SSID, exact location, IP host address, password, raw profile, or unredacted diagnostic. Use a release-local tester code such as `beta-01`.

## Machine evidence that actually closes the gate

Markdown checkboxes or three arbitrary digest strings do not close the gate.
Before approval, commit these six ordinary JSON blobs on the reviewed
pre-approval `master` commit:

```text
docs/evidence/releases/<tag>/external-beta-01.json
docs/evidence/releases/<tag>/external-beta-02.json
docs/evidence/releases/<tag>/external-beta-03.json
docs/evidence/releases/<tag>/external-beta-set.json
docs/evidence/releases/<tag>/candidate-inventory.json
docs/evidence/releases/<tag>/predecessor-lineage.json
```

Each report uses `desk-setup-switcher.external-beta/v1`. It contains only
closed, privacy-safe fields for report time, exact candidate identity, broad
environment class, independence assertions, browser/quarantine acquisition,
mandatory lifecycle results, zero-blocker state, and tester attestation. It
binds the actual release-manifest, candidate archive, final DMG, provenance
bundle, and predecessor-lineage byte digests. The report codes are exactly
`beta-01`, `beta-02`, and `beta-03`.

The set uses `desk-setup-switcher.external-beta-set/v1`. It orders the three
actual report-byte digests, names the real Sonoma gate report, and records a
protected release-approver review of a private roster. Only salted/private
roster commitments and bundle digests enter the repository; personal identity
does not. The reviewer attests that three distinct natural persons are external
to the release team and have none of the prohibited access. The validator can
prove the bindings and assertions, not the real-world identities themselves;
that last fact remains the protected reviewer trust boundary.

The candidate inventory uses `desk-setup-switcher.candidate-inventory/v1` and
the lineage uses `desk-setup-switcher.predecessor-lineage/v2`. Together they
represent retained and non-retained prior protected candidates without fake
artifact hashes, bind the actual inventory bytes, and select the latest
installable predecessor. Inventory completeness remains a protected reviewer
trust boundary; the local validator does not query GitHub.

## Generate rejected-placeholder JSON safely

The dedicated template CLI owns a stdout-only scaffold generator, isolated
from the verification policy, so an operator does not need to reconstruct
closed JSON objects from tests. It prints exactly one pretty JSON document plus
a final newline, reads no candidate or host data, writes no file, computes no
evidence digest, and never marks a gate complete. Every document contains reserved
`<REJECTED_TEMPLATE:REPLACE_REQUIRED:...>` values plus independent false or
invalid gates. `verify-set` rejects the reserved values explicitly.

Available complete-document shapes are:

| Kind | Extra options | Use |
| --- | --- | --- |
| `candidate-inventory-empty` | none | Reviewed history has no earlier consumed build |
| `candidate-inventory-retained` | none | Inventory with one retained-item shape; duplicate the item only for real reviewed rows |
| `candidate-inventory-not-retained` | none | Inventory with one non-retained-item shape |
| `predecessor-lineage-none` | none | No installable predecessor after complete review |
| `predecessor-lineage-recorded` | none | Latest installable predecessor is recorded |
| `external-beta-report-none` | `--report-code`, `--coverage-role` | Report paired with approved first-beta no-predecessor lineage |
| `external-beta-report-recorded` | `--report-code`, `--coverage-role` | Report paired with a recorded predecessor |
| `external-beta-set` | `--sonoma-report-code` | Protected review of the three completed reports |

Preview the required shape in the terminal:

```sh
ruby scripts/release/external_beta_template_cli.rb \
  --kind external-beta-report-none \
  --report-code beta-01 \
  --coverage-role sonoma-full-lifecycle

ruby scripts/release/external_beta_template_cli.rb \
  --kind external-beta-report-none \
  --report-code beta-02 \
  --coverage-role additional-apple-silicon

ruby scripts/release/external_beta_template_cli.rb \
  --kind external-beta-set \
  --sonoma-report-code beta-01
```

Use `external-beta-report-recorded` instead when lineage records an installable
predecessor. Generate the third report with `beta-03`; each code appears once,
and only the report that actually ran the full macOS 14 lifecycle may be named
as the Sonoma report.

The stdout is a structure reference, not evidence. Inspect it first, then copy
it into a new file through the protected review/editor workflow. Do not use a
plain shell `>` redirection against a canonical evidence path: the shell can
truncate an existing file before this read-only generator starts. Do not
commit any reserved placeholder. The public-history audit rejects this marker
under `docs/evidence/releases/`, and the publication verifier independently
rejects it.

Fill only facts actually observed or reviewed. Bind actual bytes in dependency
order—inventory, lineage, three reports, then set—and run `verify-set` below.
Only its successful descriptor-bound result may feed publication approval; a
generated document, edited document, or calculated digest by itself closes no
gate.

The publication helper re-reads all six files as descriptor-bound ordinary
files, validates their exact schema and chronology, calculates their actual
SHA-256 values, and cross-checks them with the restored release candidate and
`publication-approval/v2` immediately before the sole publication mutation.
Missing/extra/duplicate fields, report reuse, a wrong candidate, failed
quarantine or lifecycle state, missing Sonoma coverage, a non-independent
tester, unresolved P0/P1, or changed bytes stop publication.

The same deterministic check can be rehearsed without GitHub mutation:

```sh
ruby scripts/release/external_beta_policy.rb verify-set \
  --release-manifest artifacts/release/release-manifest.json \
  --provenance-bundle artifacts/release/Desk-Setup-Switcher-0.1.0.provenance.sigstore.json \
  --candidate-inventory docs/evidence/releases/v0.1.0/candidate-inventory.json \
  --predecessor-lineage docs/evidence/releases/v0.1.0/predecessor-lineage.json \
  --set-manifest docs/evidence/releases/v0.1.0/external-beta-set.json \
  --report docs/evidence/releases/v0.1.0/external-beta-01.json \
  --report docs/evidence/releases/v0.1.0/external-beta-02.json \
  --report docs/evidence/releases/v0.1.0/external-beta-03.json \
  --repository GGULBAE/desk-setup-switcher \
  --tag v0.1.0 --commit '<exact-tag-commit>' \
  --candidate-run-id '<origin-run-id>' \
  --candidate-artifact-id '<origin-artifact-id>' \
  --candidate-artifact-sha256 '<candidate-archive-sha256>' \
  --final-dmg-sha256 '<final-dmg-sha256>' \
  --profile-schema-version 1
```

The placeholders are intentionally rejected until replaced with exact protected
candidate values. This command is read-only and does not install, launch,
mount, publish, or mutate a system setting.

## Report identity

| Field | Recorded value |
| --- | --- |
| Tester code | `<not recorded>` |
| External relationship confirmed | [ ] Not release operator or approver |
| Test date | `<not recorded>` |
| macOS version | `<not recorded>` |
| Hardware class | Apple Silicon, broad class only |
| Minimum-OS coverage role | Sonoma 14.x gate / additional Apple Silicon report |
| Clean account/Mac basis | `<not recorded>` |
| Candidate version/build | `<not recorded>` |
| Commit and protected workflow run | `<not recorded>` |
| Workflow artifact ID | `<not recorded>` |
| Final DMG expected SHA-256 | `<not recorded>` |
| Final-DMG provenance attestation bundle/URL and subject digest | `<not recorded>` |

## Browser download and quarantine validity

- [ ] The tester opened the protected workflow run in a normal browser and downloaded its artifact archive; no push permission or secret was supplied.
- [ ] The archive was extracted through the normal macOS path.
- [ ] Before mounting, the extracted DMG had a real `com.apple.quarantine` extended attribute. The tester recorded a sanitized presence/value transcript below.
- [ ] The tester did not add, delete, copy around, or otherwise manufacture the quarantine attribute.
- [ ] The extracted DMG SHA-256 equals the expected final SHA-256.
- [ ] The final-DMG provenance attestation verifies that same final SHA-256 and protected workflow run.

Sanitized quarantine evidence: `<not recorded>`

If the extracted DMG did not actually carry quarantine, stop. Do not add it manually and do not count this report.

## Mandatory lifecycle results

Use synthetic profile names and values. Do not choose Apply or mutate display, audio, network, TCC, login-item, or Keychain state unless a separate interactive approval explicitly authorizes that named action. Checking that launch at login starts off does not authorize enabling it.

| Step | Expected result | Actual sanitized result | Pass |
| --- | --- | --- | --- |
| Checksum before mount | Exact final DMG SHA-256 | `<not recorded>` | [ ] |
| Gatekeeper/open | Identified Developer ID publisher; no Open Anyway | `<not recorded>` | [ ] |
| Clean first launch | Menu-bar-only app appears normally | `<not recorded>` | [ ] |
| Login default | Launch at login is off | `<not recorded>` | [ ] |
| Three-step explanation | Capture → Edit → Review is understandable; stop before Apply | `<not recorded>` | [ ] |
| Upgrade | Recorded installable predecessor upgrades without losing schema-1 profiles, settings, selection, backups, or consent state; only a validator-approved first-public-beta lineage may record not applicable | `<not recorded>` | [ ] |
| Schema migration | Synthetic schema 0 migrates to schema 1 without system-setting mutation | `<not recorded>` | [ ] |
| Backup recovery | With app closed, synthetic primary corruption recovers last-known-good and quarantines safely | `<not recorded>` | [ ] |
| Import/export | Import replacement and no-overwrite export behave as documented | `<not recorded>` | [ ] |
| Diagnostics | Browse/refresh/clear works and submitted evidence stays redacted | `<not recorded>` | [ ] |
| Uninstall | Optional login item is off, app quits, and app bundle is removed | `<not recorded>` | [ ] |
| Optional data removal | App-owned support data/preferences can be removed; external exports remain | `<not recorded>` | [ ] |

## Issues and severity

Use the definitions in [Distribution](DISTRIBUTION.md): P0 stops testing/publication; P1 blocks release. Do not put suspected vulnerabilities, unsafe mutations, privacy leaks, exposed secrets, or rollback failures in a public issue—follow [SECURITY.md](../SECURITY.md).

| Sanitized issue reference | Proposed severity | Resolution candidate/build | Retest result |
| --- | --- | --- | --- |
| None recorded | — | — | — |

- [ ] No unresolved P0 exists for this report.
- [ ] No unresolved P1 exists for this report.
- [ ] Every failure is linked to a sanitized public issue or privately acknowledged security record as appropriate.

## Tester attestation

- [ ] I tested the version/build, final DMG SHA-256, and final-DMG provenance attestation recorded above.
- [ ] I used a browser-downloaded workflow artifact whose extracted DMG actually retained quarantine.
- [ ] I did not use Open Anyway, disable Gatekeeper, remove quarantine, or receive repository push/secrets access.
- [ ] My recorded minimum-OS coverage role is accurate; if this is the Sonoma gate report, the recorded macOS version is 14.x and every mandatory lifecycle row above passed.
- [ ] I removed personal/device/network/location/path data from this report.
- [ ] I understand that this report does not provide hardware-mutation evidence.

When [the predecessor-lineage contract](PREDECESSOR-LINEAGE.md) proves there is
no installable predecessor for the first public beta, record the upgrade result
as `not-applicable` with the exact reason
`first-public-beta-no-installable-predecessor`. Clean install, schema migration,
recovery, import/export, diagnostics, and uninstall still must pass. If any
retained inventory item was development-installed, protected-beta installed,
or published, that exception is rejected and the latest installable
predecessor must be tested.

Tester code/date: `<not recorded>`
