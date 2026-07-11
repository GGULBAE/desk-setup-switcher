# Repository instructions

These instructions apply to the whole repository.

## Safety first

- Never run live display, audio, network, mouse, or keyboard mutations as part of ordinary development, tests, CI, or review.
- Live mutation tests require an explicit environment flag, an interactive user action, a preflight snapshot, and a documented rollback path.
- Do not add automatic profile switching, telemetry, analytics, cloud services, arbitrary shell execution, UI automation, private APIs, or edits to third-party app configuration.
- Do not persist secrets. Use a `SecretStore` abstraction backed by Keychain; keep synthetic secrets out of fixtures and logs as well.
- Treat imported profile JSON as untrusted input and keep permission denial nonfatal for unrelated features.

## Architecture

- Keep SwiftUI/AppKit in the app layer, pure profile/condition/transaction logic in `DeskSetupCore`, and macOS framework calls in concrete system adapters.
- Core owns adapter protocols and typed capability/result models. UI must not call system framework mutations directly.
- Preserve `snapshot`, `validate`, `plan`, `apply`, `rollback`, `capability`, and `diagnostics` semantics for every adapter.
- Runtime device handles and `CGDirectDisplayID` values are not persistent identity by themselves.
- Any use of an undocumented preference key must live behind an experimental capability and be documented in the support matrix.

## Quality bar

- Update README, roadmap, support matrix, and completion ledger when behavior or verification status changes.
- Add deterministic unit/mock integration tests for new domain behavior and failure paths.
- Keep live tests opt-in and read-only by default.
- Run the repository's primary `verify` command and `git diff --check` before committing.
- Do not check a completion item without committed evidence. Distinguish mock verification from hardware verification.
- Keep user-facing strings localizable and provide English and Korean values for new UI copy.
- Include accessibility labels, keyboard behavior, and non-color state cues with UI changes.

## Git hygiene

- Preserve unrelated user changes and stage only the intended milestone.
- Use concise, behavior-focused commits after verification passes.
- Never commit credentials, personal device identifiers, real SSIDs, exact locations, or unredacted diagnostics.
