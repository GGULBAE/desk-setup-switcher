# External clean-install beta report template

Use one copy per external tester. A report counts toward the three-report public-beta gate only when every mandatory row passes for the identical final stapled DMG. At least one of the three accepted reports must cover the full lifecycle on Apple Silicon/macOS 14 Sonoma; selecting a macOS 14.0 deployment target is not runtime evidence. The tester must not be the release operator or release approver and does not need push, release, environment, or secret access.

Do not include a personal name, account name, home path, serial number, device UID, real SSID, exact location, IP host address, password, raw profile, or unredacted diagnostic. Use a release-local tester code such as `beta-01`.

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
| Upgrade | Recorded predecessor build upgrades without losing schema-1 profiles, selection, backups, or consent state | `<not recorded>` | [ ] |
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

Tester code/date: `<not recorded>`
