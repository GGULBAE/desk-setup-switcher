# Profile JSON schema and interchange guide

Last updated: 2026-07-18

Desk Setup Switcher stores and exchanges one JSON `ProfileDocument`. The current format is `schemaVersion: 1`. It is intended for this app's import, export, backup, and recovery paths; it is **not** a stable third-party automation API, public SDK, or plug-in format.

For the `0.1.x` line, schema 1 is the app's readable and writable interchange format. That promise does not make the Swift types or their synthesized `Codable` representation a general compatibility surface. Older apps may reject newer schemas, unknown fields are not preserved when a document is decoded and re-exported, and forward compatibility is not promised. Use an export from the target app version as the canonical shape instead of generating JSON from this document alone.

The implementation sources are:

- [`ProfileDocument` and `DeskProfile`](../Sources/DeskSetupCore/Models/Profile.swift)
- [setting and identity models](../Sources/DeskSetupCore/Models/Settings.swift)
- [condition models](../Sources/DeskSetupCore/Models/Conditions.swift)
- [JSON codec](../Sources/DeskSetupCore/Storage/ProfileJSONCodec.swift)
- [migration](../Sources/DeskSetupCore/Storage/ProfileDocumentMigrator.swift)
- [semantic and resource validation](../Sources/DeskSetupCore/Storage/ProfileDocumentValidator.swift)
- [applicability normalization](../Sources/DeskSetupCore/Models/ProfileApplicabilityNormalizer.swift)
- [secure import and exclusive export](../Sources/DeskSetupCore/Storage/ProfileImportExport.swift)

## Canonical encoding

`ProfileJSONCodec` emits UTF-8 JSON with sorted keys, indentation, and unescaped slashes. UUIDs use their standard string representation. Dates are ISO-8601 UTC strings with nine fractional-second digits. The decoder also accepts the legacy whole-second form and ISO-8601 fractional seconds with one through nine digits.

A current empty document encoded by the app has this shape:

```json
{
  "profiles": [],
  "schemaVersion": 1,
  "updatedAt": "2023-11-14T22:13:20.000000000Z"
}
```

`selectedProfileID` is omitted when it is `null`. A normal export contains the non-optional nested setting groups and options even when they are dormant. Swift enums such as `DisplayMirroring`, `IPv4Configuration`, and `ProfileConditionKind` use the app's synthesized `Codable` representation; copy that representation from a same-version export rather than treating an example as a separate specification.

For additive schema-1 compatibility, a missing display `colorProfile`, any missing `AudioProfileSettings` leaf, and missing `NetworkProfileSettings` leaves decode to their excluded defaults. Other missing required keys still fail decoding; do not infer that arbitrary partial objects are accepted.

## Document and profile fields

### `ProfileDocument`

| JSON field | Swift value | Meaning |
| --- | --- | --- |
| `schemaVersion` | `Int` | Must decode or migrate to exactly `1`. |
| `profiles` | `[DeskProfile]` | Ordered saved profiles; profile IDs must be unique. |
| `selectedProfileID` | `UUID?` | Optional selection; when present it must identify an entry in `profiles`. |
| `updatedAt` | `Date` | Last document update timestamp. |

### `DeskProfile`

| JSON field | Swift value | Meaning |
| --- | --- | --- |
| `id` | `UUID` | Stable profile identity. |
| `name` | `String` | Required, non-blank user-facing name. |
| `profileDescription` | `String` | User-authored description; it may be empty. |
| `symbolName` | `String` | Required, non-blank SF Symbol name used by the app. |
| `isEnabled` | `Bool` | Retained for schema-1 round trips; automatic activation is not a product behavior and decode normalization sets this to `true`. |
| `settings` | `ProfileSettings` | Display, audio, network, and input group values. |
| `conditions` | `ProfileConditionSet` | Legacy readiness-condition data retained for round trips. The current manual workflow keeps it dormant and non-blocking. |
| `createdAt` | `Date` | Profile creation timestamp. |
| `updatedAt` | `Date` | Profile update timestamp. |
| `lastApplication` | `ApplicationSummary?` | Optional local result history from the most recent apply. |

`ApplicationSummary` contains `appliedAt`, a `ProfileReadiness` status (`ready`, `partial`, `unavailable`, `applying`, `applied`, or `failed`), and `items`. Each `ApplicationItemSummary` contains `id`, `group`, `key`, `status`, and a user-facing `message`; item status is `succeeded`, `failed`, `skipped`, `unsupported`, `rolledBack`, or `rollbackFailed`. These fields are result history, not instructions to the apply engine.

## Settings structure

Every setting group is a `SettingGroupConfiguration<Value>` object with:

- `isIncluded: Bool`
- `value: Value`

Every leaf is a `SettingOption<Value>` with the same two fields. A decoded document is normalized before use: group inclusion is recomputed from actionable included leaves, so manually forcing only the group flag does not make dormant values executable. A stored field is not evidence that the running Mac can read or apply it; runtime adapter capability and validation remain authoritative.

### Display

`settings.display.value` is `DisplayProfileSettings` with `displays: [DisplayTargetSettings]`.

Each display target contains:

| Field | Swift value |
| --- | --- |
| `id` | `UUID` |
| `identity` | `DisplayIdentity` |
| `isPrimary` | `SettingOption<Bool>` |
| `origin` | `SettingOption<DisplayPoint>` |
| `mirroring` | `SettingOption<DisplayMirroring>` |
| `mode` | `SettingOption<DisplayMode>` |
| `colorProfile` | `SettingOption<ColorSyncProfileTarget?>` |
| `rotationDegrees` | `SettingOption<Int>` |
| `isActive` | `SettingOption<Bool>` |

`DisplayIdentity` contains optional `uuid`, `vendorID`, `modelID`, `serialNumber`, and `productName`, plus `isBuiltIn`. A runtime `CGDirectDisplayID` is deliberately not persisted. `DisplayPoint` contains integer `x` and `y`. `DisplayMode` contains logical `width`/`height`, pixel `pixelWidth`/`pixelHeight`, and `refreshRate`. `DisplayMirroring` is either `extended` or `mirrors(DisplayIdentity)`.

`ColorSyncProfileTarget` stores `registeredProfileID`, `fileSHA256`, and `displayName`. A runtime ICC file URL is resolved from the current ColorSync catalog and is not stored in profile JSON.

### Audio

`settings.audio.value` is `AudioProfileSettings`:

| Field | Swift value |
| --- | --- |
| `defaultInputUID` | `SettingOption<String?>` |
| `defaultOutputUID` | `SettingOption<String?>` |
| `systemOutputUID` | `SettingOption<String?>` |
| `inputVolume` | `SettingOption<Double?>` |
| `outputVolume` | `SettingOption<Double?>` |
| `outputMuted` | `SettingOption<Bool?>` |

Audio identities are Core Audio UIDs, not transient device handles. Absent additive audio keys decode as excluded `null` values.

### Network

`settings.network.value` is `NetworkProfileSettings`:

| Field | Swift value |
| --- | --- |
| `wifiPower` | `SettingOption<Bool?>` |
| `wifiSSID` | `SettingOption<String?>` |
| `serviceIPv4` | `[NetworkServiceIPv4Settings]` |
| `ipv4` | `SettingOption<IPv4Configuration?>` |
| `dnsServers` | `SettingOption<[String]>` |
| `webProxy` | `SettingOption<ProxyConfiguration?>` |
| `secureWebProxy` | `SettingOption<ProxyConfiguration?>` |

Each `serviceIPv4` entry contains a portable `identity` and a `configuration` option. `NetworkServiceIdentity` contains `kind` (`ethernet` or `wifi`), `serviceName`, and `interfaceType`; runtime service IDs and BSD interface names are not persisted as identity. `IPv4Configuration` is `dhcp` or `manual(address:subnetMask:router:)`. A `ProxyConfiguration` contains `enabled`, `host`, and `port`.

### Input

`settings.input.value` is `InputProfileSettings`:

| Field | Swift value |
| --- | --- |
| `pointerSpeed` | `SettingOption<Double?>` |
| `naturalScrolling` | `SettingOption<Bool?>` |
| `keyRepeatInterval` | `SettingOption<Double?>` |
| `initialKeyRepeatDelay` | `SettingOption<Double?>` |
| `useStandardFunctionKeys` | `SettingOption<Bool?>` |

These fields remain in schema 1 for decode and round-trip compatibility. They are not actionable in the default `v0.1.0` product surface.

## Current applicability policy

`ProfileApplicabilityNormalizer` preserves values for inspection and round trips but disables inclusion for leaves that the current product must not apply. After import or decode, the actionable schema-1 leaves are:

| Group | Inclusion may remain actionable | Preserved but forced dormant |
| --- | --- | --- |
| Display | primary display, mirroring, mode, ColorSync profile | origin, rotation, active state |
| Audio | default input, default output, input volume, output volume | system output, output mute |
| Network | per-service IPv4 | Wi-Fi power/SSID, legacy global IPv4, DNS, web proxy, secure web proxy |
| Input | none | every input leaf |

Primary-display selection is one global choice represented on all display targets. It remains included only when every target's `isPrimary` option is included and exactly one value is `true`, or when every target excludes it. A mixed or ambiguous state preserves values but disables all primary-display inclusion flags.

This table is an applicability boundary, not a hardware support claim. Consult [SUPPORT-MATRIX.md](SUPPORT-MATRIX.md) for implemented, mock, live-read, experimental, and unverified status.

## Conditions

`ProfileConditionSet` contains:

- `mode`: `all` or `any`
- `isInverted: Bool`
- `conditions: [ProfileCondition]`

Each condition has `id`, `kind`, and `isInverted`. Supported schema cases are:

- `displayConnected(DisplayIdentity)`
- `audioInputConnected(uid:)`
- `audioOutputConnected(uid:)`
- `hardwareConnected(identifier:)`
- `wifiSSID(String)`
- `ethernetConnected`
- `ipAddressOrCIDR(String)`
- `location(LocationRegion)` with `latitude`, `longitude`, and `radiusMeters`

The pure core evaluator retains all/any/inversion semantics for stored-data compatibility. The current `v0.1.0` manual workflow deliberately treats existing and imported conditions as dormant: they do not block readiness or Apply, the app does not expose condition editing, and conditions never trigger automatic switching.

## Migration and normalization order

Decode follows this order:

1. Reject data larger than the configured limit before parsing.
2. Require `schemaVersion` to be an explicit integer JSON number in the top-level object.
3. Migrate sequentially to the current schema.
4. Decode using the ISO-8601 date policy.
5. Run semantic and resource validation on the decoded document.
6. Normalize current applicability without discarding dormant values.
7. Validate the normalized document again.

The only current migration is an explicit schema 0 to schema 1. It replaces `"schemaVersion": 0` with `"schemaVersion": 1`; it does not guess, rename, or synthesize unrelated profile fields. Missing versions, booleans, floating or fractional number representations, negative versions, missing migration steps, and versions newer than 1 are rejected. There is no silent downgrade.

When the app loads its managed primary file, a migrated or normalized document is persisted in canonical form after identity checks. Imported data is normalized before the app offers replacement, and exports are normalized before encoding.

## Validation limits and rules

The standard resource limits are:

| Limit | Value |
| --- | --- |
| Maximum document size | 5 MiB |
| Maximum profiles | 500 |
| Maximum conditions per profile | 100 |
| Maximum validated string length | 1,024 Unicode scalars |

For settings, semantic checks apply when the group and leaf are included at that validation pass. Decode validates both before and after applicability normalization, so currently actionable leaves are checked before use. Fully dormant values may remain for round-trip compatibility without range or address validation.

Semantic validation includes, but is not limited to:

- unique profile IDs, unique condition IDs within a profile, and unique display target IDs;
- an existing `selectedProfileID`, plus non-blank profile names and symbol names;
- included optional values being present, including an actionable display ColorSync profile target;
- display origins fitting signed 32-bit coordinates, dimensions in `1...100000`, finite refresh rates in `0...1000`, and rotations in `0`, `90`, `180`, or `270` degrees;
- finite audio volumes in `0...1`;
- valid IPv4 addresses, contiguous IPv4 subnet masks, optional valid routers, valid IPv4/IPv6 DNS values, and enabled proxy ports in `1...65535`;
- finite input values in their implemented ranges when semantically enabled;
- non-blank device, SSID, and hardware condition values, plus valid IP/CIDR conditions; and
- location latitude in `-90...90`, longitude in `-180...180`, and finite radius in `0...40000000` metres.

Validation is not a capability check. A structurally valid target can still be unavailable, permission-gated, unsupported, or unmatched on the current Mac. The adapter contract handles that later during read-only preparation.

## Import behavior and trust boundary

Profile JSON is untrusted input. [`ProfileImportExport.importDocument`](../Sources/DeskSetupCore/Storage/ProfileImportExport.swift) accepts only a user-selected local file URL and uses descriptor-bound reads:

- symbolic-link leaves, user-controlled ancestor symlinks, directories, devices, FIFOs, and other non-regular objects are rejected;
- the file must be owned by the effective user; root-owned macOS compatibility directory links may be traversed, but are re-resolved and verified;
- pre-open and post-open device/inode/owner checks reject leaf replacement;
- size, modification time, change time, and identity stability are checked around the complete read; and
- an in-place rewrite or path replacement during the read fails closed.

Parser and generic I/O details are converted to typed errors that do not retain raw underlying messages. Validation reports safe field paths and reasons, not the document payload.

Importing does not apply any system setting. The app decodes the selected file first, then presents a replacement confirmation. Only explicit confirmation calls `ProfileStore.replaceAll`; cancellation leaves the current store unchanged. See the [app import coordination](../Sources/DeskSetupSwitcher/ApplicationModel.swift).

## Export behavior and recovery boundary

The app exports the authoritative persisted document; unsaved editor drafts are deliberately excluded. Export:

- normalizes and validates before encoding;
- accepts only a local file URL;
- creates a new owner-readable/writable file with exclusive-create semantics;
- refuses to overwrite any existing destination; and
- when exporting an `ImportedProfileDocument`, refuses a destination that resolves to the import source.

The current export writer writes directly to the new final path. It synchronizes and removes the file when a reported write fails, but it is not a crash-atomic export: sudden termination or power loss could leave a partial newly created file. If an export is interrupted, delete the incomplete file after inspection and export again to a new destination. This limitation does not change the managed `ProfileStore`, which separately uses a private staging file, atomic rename, a last-known-good backup, and corrupt-file quarantine.

## Privacy and safe sharing

There is no password, token, Keychain secret, or credential field in schema 1. Saved Wi-Fi association relies on credentials already held by macOS; they are never serialized into a profile.

An export is nevertheless potentially sensitive. It can contain:

- profile names, descriptions, symbols, timestamps, and last-application messages;
- display UUID/vendor/model/serial metadata and product names;
- Core Audio device UIDs;
- SSIDs in stored values or conditions;
- network service labels, IP addresses/ranges, routers, DNS values, and proxy hosts;
- hardware identifiers; and
- exact latitude/longitude centers with a radius.

Exports are not passed through diagnostic redaction and are not uploaded by the app. Review or remove private desk labels, device identifiers, SSIDs, network values, location conditions, and result history before sharing a file or attaching it to an issue. Use synthetic values in tests, examples, screenshots, and bug reproductions. The broader local-data policy is in [PRIVACY.md](PRIVACY.md).

## Compatibility and contributor rules

- `schemaVersion` is independent of the app's SemVer and build number.
- Schema 1 is the `0.1.x` app interchange format, not a promise that all fields are actionable.
- Do not persist runtime handles, `CGDirectDisplayID`, runtime network service IDs, BSD interface names as identity, session catalogs, operation payloads, rollback payloads, or credentials.
- A future schema change must add deterministic migration from every profile schema written by a still-supported release, retain last-known-good recovery, and add malformed/future-version/failure-path tests.
- Do not reuse `DeskSetupCore` public Swift declarations as a compatibility guarantee. The package products are internal and unstable as documented in [COMPATIBILITY.md](COMPATIBILITY.md).
- Any generated document remains untrusted and is accepted only if the target app's codec, migration, validation, normalization, and secure-file checks approve it.

Deterministic evidence for this contract lives in [migration tests](../Tests/DeskSetupCoreTests/MigrationTests.swift), [validation tests](../Tests/DeskSetupCoreTests/ProfileValidationTests.swift), [import/export tests](../Tests/DeskSetupCoreTests/ImportExportTests.swift), and [managed-store tests](../Tests/DeskSetupCoreTests/ProfileStoreTests.swift).
