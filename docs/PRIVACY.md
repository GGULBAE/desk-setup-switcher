# Privacy policy

Last updated: 2026-07-18

Desk Setup Switcher is designed to operate entirely on the Mac where it is installed.

## Data collection

The app does not create an account, contact an application server, collect analytics, send telemetry, serve advertising, or sell/share personal data. The app has no application-owned outbound network feature.

## Local data

Profiles, settings, backups, corruption quarantine files, and redacted diagnostics are stored under `~/Library/Application Support/Desk Setup Switcher/`. App-managed profile/quarantine/diagnostic directories use owner-only 0700 permissions and their managed files use 0600. Imports are read from, and exports are written to, locations the user explicitly selects. Removing the app does not automatically delete these files. The Diagnostics Settings pane can browse, refresh, and clear the app-managed sanitized diagnostic files.

Profiles may contain device identifiers needed for stable matching, selected SSID condition values, network ranges, and location-condition centers stored as exact latitude/longitude coordinates plus a radius. Import/export preserves those profile values; diagnostic redaction does not rewrite an exported profile. They do not contain Wi-Fi passwords or other credentials.

Treat exported profiles as potentially sensitive. Before sharing one, review or remove desk/device labels, SSIDs, network ranges, and location conditions. An exact location-condition center can identify a home, office, or other private place even though the app does not upload it.

## Credentials

Passwords are never model fields and are never written to profile JSON, backups, exports, operations, or logs. Saved Wi-Fi association uses credentials already managed by macOS rather than asking the app to store a password. A separate Security-framework Keychain boundary exists for future secret references and is mock tested with synthetic bytes; its live write test has deliberately not been run.

## Permissions

The app requests the minimum permission needed for a selected feature and explains the reason before triggering the system prompt. Location permission may be required by macOS to read an SSID or evaluate a location condition. Denial disables only the dependent value or condition. Listing or selecting an audio input device does not capture audio and does not require microphone recording permission.

## Diagnostics

Diagnostics are local and rotate by size/count. Before writing, the app removes credentials, precise location, SSIDs, host portions of IP addresses, home-directory paths, and Keychain data. This protection applies to diagnostic entries, not to the user's profile JSON. The current UI supports local browsing, refresh, and clearing; diagnostic export is not currently implemented. No diagnostic is uploaded automatically.

## Network configuration

Reading local interface state is not telemetry. The app does not probe internet hosts or use external IP/geolocation services. Applying a saved Wi-Fi selection can cause macOS to communicate with that network only after the user explicitly applies a profile.

## Open-source review

The implementation and its permission declarations are public under the MIT License. Security and privacy reports must follow [SECURITY.md](../SECURITY.md). Do not put report details in a public issue; that policy records the currently available private-contact path and the repository setting that must be enabled before public launch.

## Current status

The pre-release implementation follows the local-only architecture: no app-owned `URLSession`, telemetry, analytics, account, or cloud path exists; profile/diagnostic storage and redaction tests pass. The locally packaged app launches, but no public release exists. Permission-denied behavior, downloaded/quarantined install behavior, and clean-user removal/clearing still require manual verification, and live hardware tests must keep their evidence redacted. The [evidence ledger](COMPLETION-CRITERIA.md) tracks conformance without treating source, mocks, or read-only discovery as mutation proof.
