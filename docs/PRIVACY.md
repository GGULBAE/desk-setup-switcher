# Privacy policy

Last updated: 2026-07-11

Desk Setup Switcher is designed to operate entirely on the Mac where it is installed.

## Data collection

The app does not create an account, contact an application server, collect analytics, send telemetry, serve advertising, or sell/share personal data. The app has no application-owned outbound network feature.

## Local data

Profiles, settings, backups, and redacted diagnostics are stored under the app's directory in the current user's Application Support folder. Imports are read from, and exports are written to, locations the user explicitly selects. Removing the app does not automatically delete these files.

Profiles may contain device identifiers needed for stable matching, selected SSID condition values, and network ranges. They do not contain Wi-Fi passwords or other credentials. A user should review an exported profile before sharing it because desk and network names can still be identifying.

## Credentials

When a feature requires a credential reference, the credential is stored in macOS Keychain. Passwords are never written to profile JSON, backups, exports, or logs. The app prefers credentials already managed by macOS for saved Wi-Fi networks.

## Permissions

The app requests the minimum permission needed for a selected feature and explains the reason before triggering the system prompt. Location permission may be required by macOS to read an SSID or evaluate a location condition. Denial disables only the dependent value or condition. Listing or selecting an audio input device does not capture audio and does not require microphone recording permission.

## Diagnostics

Diagnostics are local and rotate by size/count. Before writing, the app removes credentials, precise location, unnecessary SSIDs, host portions of IP addresses, home-directory paths, and Keychain data. Users choose whether to export diagnostics. No diagnostic is uploaded automatically.

## Network configuration

Reading local interface state is not telemetry. The app does not probe internet hosts or use external IP/geolocation services. Applying a saved Wi-Fi selection can cause macOS to communicate with that network only after the user explicitly applies a profile.

## Open-source review

The implementation and its permission declarations are public under the MIT License. Security/privacy reports should follow [../SECURITY.md](../SECURITY.md) once that file is present.

## Current status

The repository is pre-alpha. This policy is the required implementation contract, not a claim that an installable release already exists. The evidence ledger tracks conformance.
