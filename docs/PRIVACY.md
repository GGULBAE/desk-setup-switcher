# Privacy policy

Last updated: 2026-09-12

Desk Setup Switcher is designed to operate entirely on the Mac where it is installed.

## Data collection

The app does not create an account, contact an application server, collect analytics, send telemetry, serve advertising, or sell/share personal data. The app has no application-owned outbound network feature.

## Local data

Profiles, settings, backups, corruption quarantine files, and redacted diagnostics are stored under `~/Library/Application Support/Desk Setup Switcher/`. App-managed profile/quarantine/diagnostic directories use owner-only 0700 permissions and their managed files use 0600. Imports are read from, and exports are written to, locations the user explicitly selects. Removing the app does not automatically delete these files. The Diagnostics Settings pane can browse, refresh, and clear the app-managed sanitized diagnostic files.

Profiles may contain device identifiers needed for stable matching, selected or dormant SSID values, network ranges, and imported legacy location-condition centers stored as exact latitude/longitude coordinates plus a radius. The current UI does not create or evaluate location conditions, but import/export preserves dormant legacy values for compatibility; diagnostic redaction does not rewrite an exported profile. Profiles do not contain Wi-Fi passwords or other credentials.

Treat exported profiles as potentially sensitive. Before sharing one, review or remove desk/device labels, SSIDs, network ranges, and dormant legacy location conditions. A preserved exact legacy center can identify a home, office, or other private place even though the app does not upload it.

## Credentials

Passwords are never model fields and are never written to profile JSON, backups, exports, operations, or logs. Current profiles do not capture or apply Wi-Fi/network settings and do not request a Wi-Fi password. A separate Security-framework Keychain boundary exists for future secret references and is mock tested with synthetic bytes; its live write test has deliberately not been run.

## Permissions

Current Capture reads only main display, resolutions, output device/volume, and input device/volume. It does not request Location permission or store network settings in new profiles; existing Location authorization does not gate capture. The app does not request or store coordinates. Listing or selecting an audio input device does not capture audio and does not require microphone recording permission. Dormant location conditions in older imported files remain a separate compatibility/privacy concern.

## Diagnostics

Diagnostics are local and rotate by size/count. Before writing, the app removes credentials, precise location, SSIDs, host portions of IP addresses, home-directory paths, and Keychain data. This protection applies to diagnostic entries, not to the user's profile JSON. The current UI supports local browsing, refresh, and clearing; diagnostic export is not currently implemented. No diagnostic is uploaded automatically.

## Network configuration

No network setting is part of current profile Capture, Edit, or Apply, including imported service IPv4/Wi-Fi values and Force mode. Historical local network/condition primitives may remain for read-only diagnostics or compatibility tests; they are not telemetry, internet probes, or profile mutations. The app does not use external IP/geolocation services.

## Public project site

The public project site is separate from the app. The project code sets no cookie and includes no project analytics, advertising, fingerprinting, or client-side tracking. It does not persist product or visitor data in browser storage. The bundled vinext router has two technical, tab-scoped `sessionStorage` guards that may briefly store only the current path or hard-navigation target to prevent navigation/reload loops and then remove it. Their exact key names and calls are pinned by the built-client test.

The public holding page is hosted as static files on GitHub Pages at
<https://ggulbae.github.io/desk-setup-switcher/>. GitHub handles each request
and states that it logs a visitor's IP address for security. GitHub may process
other service-usage information under its own terms. Those provider operations
are not app telemetry or project product analytics, and the project does not
receive or maintain a per-visitor analytics database. Review GitHub's
[Pages data-collection notice](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
and [General Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

The separate owner-only preview uses a Worker-compatible Sites build with no
Analytics Engine, database, object-storage, or external-service binding and
disables Worker logs/traces. Its hosting provider may still process requests
and retain aggregate platform metrics. The public GitHub Pages branch deployment
neither uses that preview configuration nor deploys through the user's
Cloudflare account. See the [GitHub Pages publication contract](GITHUB-PAGES-PUBLICATION.md)
for the complete hosting boundary.

## Open-source review

The implementation and its permission declarations are public under the MIT License. Security and privacy reports must follow the current [SECURITY.md](../SECURITY.md) instructions. Private vulnerability reporting is currently disabled: request a private channel without including report details in the initial contact or a public issue. That policy records the repository setting that must be enabled and tested before public launch.

## Current status

The pre-release implementation follows the local-only architecture: no app-owned `URLSession`, telemetry, analytics, account, or cloud path exists; profile/diagnostic storage and redaction tests pass. A historical locally packaged build launched, but the current development-evidence package was not installed or launched and no public release exists. Permission-denied behavior, downloaded/quarantined install behavior, and clean-user removal/clearing still require manual verification, and live hardware tests must keep their evidence redacted. The [evidence ledger](COMPLETION-CRITERIA.md) tracks conformance without treating source, mocks, or read-only discovery as mutation proof.
