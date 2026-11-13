# Selective-settings reinstall and DMG delivery — 2026-11-13

The user requested reinstalling and distributing the UI improvements, then clarified the existing simple DMG delivery model. The chosen output is a development-preview DMG and checksum, separate from the supported v0.1.0 beta lifecycle gate.

## Local installation

- The verified 0.0.9/build-1 universal package was mounted read-only, copied to a private staging folder, and checked with strict/deep signature verification.
- The old app quit normally through NSRunningApplication. No force quit, draft dismissal, Capture, Apply, permission request, or hardware mutation was used.
- The old app, both profile files, and app-owned preferences were backed up privately before replacement. Recovery instructions are retained with those backups, outside tracked source.
- The replacement at `/Applications/Desk Setup Switcher.app` passed signature verification and matched the packaged executable digest `627f3cd95cd62bc15d6487b49f08888bf810a8921aea6b795942bfc3f16c35b8`.
- The DMG was ejected before launch. NSRunningApplication confirmed one process using the exact installed executable path.
- Startup normalized retired-setting applicability. Profile bytes changed, while comparison confirmed that all stored values, profile metadata other than applicability/timestamps, and the profile count were preserved. Personal profile contents and identifiers are omitted from this record.

App-only rollback: quit the replacement normally, retain it separately, and restore the privately backed-up previous app. Do not overwrite profile files to roll back the application, because that could discard subsequent edits.

## Delivery boundary

The current UI source passed complete non-live `make verify` and `git diff --check` before installation. Public-copy and privacy/history checks are additionally required before pushing the release source. Only the exact successful CI package pair will be attached to the versioned GitHub development prerelease; a supported macOS 14 lifecycle or hardware result is not claimed. The informational site's v0.1.0 release state remains holding.
