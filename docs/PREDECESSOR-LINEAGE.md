# Build number, candidate inventory, and predecessor lineage

The first public-beta path is fixed to two protected candidates:

| Role | Tag | App version | Build | Distribution state |
| --- | --- | --- | --- | --- |
| Upgrade predecessor | `v0.0.9` | `0.0.9` | `1` | `protected-beta`; retained, never a GitHub Release |
| Final public beta | `v0.1.0` | `0.1.0` | `2` | Final protected candidate; the only draft/public Release |

There is no first-beta “no predecessor” exception. Publication requires a real
upgrade from the exact retained build-1 predecessor to the exact build-2 final
candidate.

The reviewed pre-approval `master` commit contains these two machine-readable
records:

```text
docs/evidence/releases/v0.1.0/candidate-inventory.json
docs/evidence/releases/v0.1.0/predecessor-lineage.json
```

They are release evidence, not product configuration. Both must be ordinary
tracked JSON blobs before the `pre-publication` remote-controls snapshot is
collected. The publication helper reads their exact bytes without following
links, validates them against both restored attempt-1 origin artifacts, and
requires the reports, set, and final approval to bind the calculated digests.

## Build-number rule

`CFBundleVersion` is one canonical positive decimal integer. Zero, leading
zeroes, signs, whitespace, and dotted values are rejected. The number is global
across app versions and must be greater than every earlier protected
`build-candidate` attempt-1 dispatch. Gaps are permitted by the general rule;
reuse is not. The fixed first-beta policy narrows that rule to build 1 for
`v0.0.9` and build 2 for `v0.1.0`.

A protected candidate dispatch consumes its recorded number even when it fails,
is cancelled, is abandoned, or its artifact is no longer retained. Restoring
the exact origin run/artifact byte-for-byte is the only operation that retains a
number. A rebuild, new signing dispatch, changed app bytes, or unavailable
origin artifact requires a greater number and therefore cannot satisfy this
fixed first-beta pair.

The local validator proves that the supplied inventory is closed-schema,
strictly ordered, unique, and lower than the current build. It cannot query
GitHub or prove that a human-supplied history omitted no run. Completeness is a
protected release-approver trust boundary, backed by the private sanitized
source receipt named in the inventory. Do not describe this local check alone
as proof of complete remote history.

## Start from the policy-owned rejected shapes

The stdout-only template generator exposes exactly four document kinds across
the external-beta contract. The inventory and lineage kinds are:

```sh
ruby scripts/release/external_beta_template_cli.rb \
  --kind candidate-inventory-retained

ruby scripts/release/external_beta_template_cli.rb \
  --kind predecessor-lineage-recorded
```

There is no empty inventory, non-retained-only inventory, or no-predecessor
lineage template. Each command prints one deterministic JSON document and never
reads candidate data, writes a file, calculates a digest, or infers evidence.
Reserved `REJECTED_TEMPLATE` values, zero IDs, incomplete review flags, and
other fail-closed leaves make the output invalid.

Treat stdout as a preview/copy source. Never show a plain `>` redirection to a
canonical evidence path because it can truncate an existing record. Create new
files through the protected editor workflow, replace values only with reviewed
facts, calculate the actual inventory byte digest, bind it in lineage, then bind
the actual lineage digest in all reports and their actual digests in the set.
`verify-set` remains the only local pass decision; the generator cannot approve
a predecessor or any release gate.

## Candidate inventory v1

`candidate-inventory.json` uses
`desk-setup-switcher.candidate-inventory/v1`. Its root contains exactly:

```text
schemaVersion
subject
collection
items
```

`subject` binds the repository,
`.github/workflows/signed-release-candidate.yml`, the `build-candidate`
operation, and the current candidate's run ID and integer build. For this
release, the current identity is exactly `v0.1.0`, build 2. `collection` records
canonical collection/review times, the exact
`protected-complete-history-review` mode, `release-approver` role,
`allPagesReviewed: true`, and the SHA-256 of the sanitized protected source
receipt. Collection cannot predate the current candidate manifest, review
cannot predate collection, and every listed run's completion must be strictly
earlier than the current candidate manifest creation time and no later than
collection.

The fixed inventory contains exactly one item: a successful, retained
`v0.0.9`, build-1, attempt-1 origin with `distributionState:
"protected-beta"`. It binds the predecessor commit, completion time, run ID,
artifact ID, candidate-archive SHA-256, final-DMG SHA-256, and release-manifest
SHA-256. The predecessor run ID and every retained identity must differ from the
current build-2 origin.

The underlying closed item schema can represent failed, cancelled, abandoned,
or non-retained runs, but no such alternate item can replace or accompany the
fixed predecessor in this release: build numbers are positive and unique, every
historical build must be below 2, and build 1 is already reserved by the
required retained predecessor.

## Predecessor lineage v3

`predecessor-lineage.json` uses
`desk-setup-switcher.predecessor-lineage/v3` and contains exactly:

```text
schemaVersion
candidate
candidateInventorySHA256
upgradePredecessor
```

`candidate` repeats the exact repository, `v0.1.0` tag and commit, app version
`0.1.0`, integer build 2, bundle identifier, profile schema, origin
run/artifact identity, candidate-archive digest, final-DMG digest, and current
release-manifest digest. The verifier derives those expected values from
protected workflow inputs and the actual restored current manifest; the JSON
does not authorize itself.

`candidateInventorySHA256` is calculated from the descriptor-read inventory
bytes. Changing the inventory invalidates the lineage, all three beta reports,
their set, and the final publication approval.

`upgradePredecessor` is always `state: "recorded"` and
`distributionKind: "protected-beta"`. It binds all of the following to the one
retained inventory item and the actual restored predecessor files:

- bundle identifier, version `0.0.9`, annotated tag `v0.0.9`, build 1, and
  nonnegative profile-schema version;
- source commit, attempt-1 origin run, artifact ID, and candidate-archive
  SHA-256;
- canonical `Desk-Setup-Switcher-0.0.9.dmg` name, exact final-DMG SHA-256, and
  exact predecessor release-manifest SHA-256;
- canonical `Desk-Setup-Switcher-0.0.9.provenance.sigstore.json` name, its
  exact byte digest, and the final-DMG subject digest; and
- the exact byte digest of the v3 `final-pre-tag` remote-controls evidence that
  records the annotated predecessor tag object, peeled predecessor commit,
  complete tag inventory, and zero GitHub Releases.

The caller separately supplies the exact predecessor tag-object SHA and the
SHA-256 of the earlier `predecessor-pre-tag` evidence. The v3 boundary must bind
that earlier digest. The verifier descriptor-reads the predecessor manifest,
streams and hashes the predecessor DMG, hashes the provenance bundle, checks the
manifest identity and DMG size/hash, and enforces chronology before accepting
the lineage. Workflow attestation verification remains an additional protected
workflow gate; a digest string by itself is not provenance proof.

Every external report must browser-download and verify both the final candidate
and this exact predecessor, then record a passed upgrade that preserves schema-1
profiles, settings, selection, backups, and the login-item consent boundary.

## Three-phase remote boundary and evidence order

Remote-controls evidence uses
`desk-setup-switcher.remote-release-controls-evidence/v3` and anchors four
workflow identities: the signed-candidate workflow, CI, publication, and the
disabled fail-only legacy tombstone. The release order is strict:

1. Establish the protected `v0.0.9` build-1 source commit with the reviewed
   workflow/script trees and exact CI. While no `v*` ref or GitHub Release
   exists, collect `predecessor-pre-tag` evidence outside the repository.
2. Create one annotated `v0.0.9` tag object targeting that commit and bind the
   exact predecessor-pre-tag evidence digest in its entire message. Add the
   unchanged evidence bytes at
   `docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json` in
   the required direct-child, add-only evidence commit. Never move or recreate
   the tag.
3. After separate authorization, push the already recorded predecessor tag and
   run `build-candidate` once for `v0.0.9`/build 1. Retain its exact nine-asset
   attempt-1 origin. Never create a GitHub Release for it and never rerun the
   origin.
4. Establish the descendant `v0.1.0` build-2 source commit. The critical
   `.github/workflows` and `scripts/release` trees must remain byte-identical
   across the predecessor and final tagged commits. With exactly the annotated
   `v0.0.9` ref and zero GitHub Releases, collect v3 `final-pre-tag` evidence;
   it must bind the predecessor tag object, peeled commit, and predecessor-pre-tag
   evidence digest.
5. Create one annotated `v0.1.0` tag object targeting the build-2 commit and
   bind the exact final-pre-tag evidence digest in its entire message. Add the
   unchanged bytes at
   `docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json` in the
   required direct-child, add-only evidence commit. Never move or recreate the
   tag.
6. After separate authorization, push the already recorded final tag, run its
   attempt-1 `build-candidate`, and prepare only the exact `v0.1.0` draft from
   that retained origin. Neither operation may replace the predecessor origin.
7. Restore both origins. Review the complete candidate history, retain the
   sanitized private source receipt, and create the fixed inventory and lineage.
   Run `verify-set` with the actual current manifest/DMG/provenance, actual
   predecessor manifest/DMG/provenance, predecessor tag object, predecessor-pre-tag
   digest, and final-pre-tag boundary.
8. Complete three external reports and the protected independence-review set.
   Each report binds the exact lineage and passes acquisition plus preservation
   for the recorded predecessor.
9. Commit the unchanged inventory, lineage, reports, and set before the fresh
   v3 `pre-publication` snapshot. That snapshot must bind both annotated tag
   objects, both earlier evidence digests, and the exact `v0.1.0` draft Release.
   The final approval commit may add only the pre-publication manifest and
   `publication-approval.json`; it cannot rewrite earlier evidence.

Any omitted/reused candidate, changed origin artifact, altered evidence byte,
wrong tag object, missing predecessor acquisition, failed preservation result,
or chronology inversion stops publication. Correct the evidence or start a new
higher-numbered candidate path; never move a published or protected tag and
never replace a retained or published asset.
