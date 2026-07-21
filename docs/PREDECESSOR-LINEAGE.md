# Build number, candidate inventory, and predecessor lineage

Every public-beta candidate has two machine-readable records on the reviewed
pre-approval `master` commit:

```text
docs/evidence/releases/<tag>/candidate-inventory.json
docs/evidence/releases/<tag>/predecessor-lineage.json
```

They are release evidence, not product configuration. Both must be ordinary
tracked JSON blobs before the final remote-controls snapshot is collected. The
publication helper reads their exact bytes without following links, validates
them against the restored candidate, and requires the lineage and final
approval to bind the calculated inventory digest.

## Build-number rule

`CFBundleVersion` is one canonical positive decimal integer. Zero, leading
zeroes, signs, whitespace, and dotted values are rejected. The number is global
across app versions and must be greater than every earlier protected
`build-candidate` attempt-1 dispatch. Gaps are permitted; reuse is not.

A protected candidate dispatch consumes its recorded number even when it
fails, is cancelled, is abandoned, or its artifact is no longer retained.
Restoring the exact origin run/artifact byte-for-byte is the only operation
that retains the number. A rebuild, new signing dispatch, changed app bytes, or
unavailable origin artifact requires a greater number.

The local validator proves that the supplied inventory is closed-schema,
strictly ordered, unique, and lower than the current build. It cannot query
GitHub or prove that a human-supplied history omitted no run. Completeness is a
protected release-approver trust boundary, backed by the private sanitized
source receipt named in the inventory. Do not describe this local check alone
as proof of complete remote history.

## Start from the policy-owned rejected shapes

Preview the complete current-schema inventory and lineage variants with the
stdout-only generator:

```sh
ruby scripts/release/external_beta_template_cli.rb \
  --kind candidate-inventory-empty
ruby scripts/release/external_beta_template_cli.rb \
  --kind candidate-inventory-retained
ruby scripts/release/external_beta_template_cli.rb \
  --kind candidate-inventory-not-retained

ruby scripts/release/external_beta_template_cli.rb \
  --kind predecessor-lineage-none
ruby scripts/release/external_beta_template_cli.rb \
  --kind predecessor-lineage-recorded
```

Each command prints one deterministic JSON document and never reads candidate
data, writes a file, calculates a digest, or infers which variant is true. The
reserved `REJECTED_TEMPLATE` values, zero IDs, incomplete review flags, and
other fail-closed leaves make the output invalid evidence. Choose variants
only from the complete protected history review, add one inventory item for
every real consumed build, and replace values only with reviewed facts.

Treat stdout as a preview/copy source. Never show a plain `>` redirection to a
canonical evidence path because it can truncate an existing record. After
creating new files through the protected editor workflow, calculate the actual
inventory byte digest, bind it in lineage, then bind the actual lineage digest
in all reports and their actual digests in the set. `verify-set` remains the
only local pass decision; the generator cannot approve a first-beta exception
or a predecessor.

## Candidate inventory v1

`candidate-inventory.json` uses
`desk-setup-switcher.candidate-inventory/v1`. Its root contains exactly:

```text
schemaVersion
subject
collection
items
```

`subject` binds the repository, `.github/workflows/release.yml`, the
`build-candidate` operation, and the current candidate's run ID and integer
build. `collection` records canonical collection/review times, the exact
`protected-complete-history-review` mode, `release-approver` role,
`allPagesReviewed: true`, and the SHA-256 of the sanitized protected source
receipt. Collection cannot predate the candidate manifest, review cannot
predate collection, and every listed run's completion must be strictly earlier
than the current candidate manifest creation time and no later than collection.

Every earlier consumed build appears once, in ascending order, with its
version, build, commit, attempt-1 run ID, conclusion, completion time, and
distribution state. Build numbers are unique and lower than the current
candidate. Run IDs are unique across the inventory and current candidate; the
validator does not assume that GitHub's numeric run IDs are a documented time
ordering. Items use one of two exact variants:

- `outcome: "not-retained"` represents failure, cancellation, abandonment, or
  an unavailable retained artifact. It contains no invented artifact, DMG, or
  manifest identity and must use `distributionState: "not-distributed"`.
- `outcome: "retained"` requires a successful run plus the artifact ID,
  candidate-archive digest, final-DMG digest, and release-manifest digest. Its
  distribution state is `not-distributed`, `development-installed`,
  `protected-beta`, or `published`.

Retained artifact IDs and all retained identity digests must also be unique
against the current candidate. A failed run is therefore recorded honestly
instead of being padded with fake 64-character hashes.

## Predecessor lineage v2

`predecessor-lineage.json` uses
`desk-setup-switcher.predecessor-lineage/v2` and contains exactly:

```text
schemaVersion
candidate
candidateInventorySHA256
upgradePredecessor
```

`candidate` repeats the exact repository, tag, commit, app version, integer
build, bundle identifier, profile schema, origin run/artifact identity,
candidate-archive digest, final-DMG digest, and release-manifest digest. The
verifier derives those expected values from protected workflow inputs and the
actual restored manifest; the JSON does not authorize itself.

`candidateInventorySHA256` is calculated from the descriptor-read inventory
bytes. Changing the inventory invalidates the lineage, all three beta reports,
their set, and the final publication approval.

## Upgrade predecessor states

Use `state: "recorded"` when an installable retained item exists. The selected
item must be the highest-build installable inventory item and the kind must map
exactly:

| Inventory state | Lineage kind |
| --- | --- |
| `development-installed` | `development-evidence` |
| `protected-beta` | `protected-beta` |
| `published` | `public-release` |

The record also binds bundle ID, version/build, nonnegative profile schema,
source commit, canonical `Desk-Setup-Switcher-<version>.dmg` name, final-DMG
digest, identity-evidence digest, and install-evidence digest. Every beta report
must pass upgrade preservation against that same predecessor.

Use `state: "none"` only with this exact reason:

```text
first-public-beta-no-installable-predecessor
```

That variant binds the actual candidate-inventory digest plus clean-install and
schema-0-migration evidence. It is rejected when any retained inventory item is
`development-installed`, `protected-beta`, or `published`. Earlier failed,
abandoned, or never-installed builds do not create a usable upgrade source.
The exception waives only the upgrade row; clean installation, recovery,
migration, import/export, diagnostics, uninstall, and all three beta reports
remain mandatory.

## Evidence order

1. Restore and verify the exact signed/notarized candidate and all nine assets.
2. Review the complete protected candidate-run history, retain the sanitized
   private source receipt, and create `candidate-inventory.json` without
   personal or device identifiers.
3. Create lineage v2 from the inventory's actual SHA-256 and commit both files.
4. Complete three external reports; each binds the exact lineage digest and
   either passes the recorded upgrade or uses the permitted not-applicable
   state.
5. Commit the reports and protected independence-review set before the fresh
   pre-publication remote-controls snapshot.
6. The final approval commit adds only that snapshot and
   `publication-approval.json`; it cannot rewrite inventory, lineage, or beta
   evidence.

Any omitted/reused candidate discovered during review, reused identity,
ambiguous retained artifact, changed byte, or chronology inversion stops
publication. Correct the evidence or create a higher-numbered candidate; never
move a published tag or replace a published asset.
