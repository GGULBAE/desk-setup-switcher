# P2 UI refinement audit — 2026-07-17

## Scope and result boundary

This pass implements the bounded P2 UI/UX ledger that followed the native popover and persistent-window structural fixes. It simplifies the first-run path, moves infrequent profile operations behind one secondary menu, states saved-versus-draft behavior directly, makes inclusion and disclosure state explicit, and gives minimum-size workflow/error surfaces deterministic fixtures.

Implementation and deterministic/synthetic evidence are distinct from installed-app and assistive-technology evidence:

- **Source/deterministic:** the final integrated gate passed 461 checks: 144 XCTest cases, 316 Swift Testing cases across 39 suites, and one isolated native popover regression.
- **Attached/offscreen synthetic:** fixtures use injected models, temporary storage, suppressed public actions, Korean copy, and simulated accessibility text. The reviewed manifest contains 39 fixtures and 79 artifacts: 15 tray, 13 Settings, three apply-preview, two responsive-workflow, and six auxiliary fixtures, plus one Settings footer comparison note.
- **Installed, bounded interaction:** pass. The final DMG was reinstalled; `⌘,` routed to Profiles from visible System/About and across close→reopen and stale cases; the bounded disclosure keyboard/AX check passed. No Apply Profile, Capture, TCC, login-item change, or display/ColorSync/audio/network/input mutation ran.
- **Disclosure accessibility boundary:** VoiceOver was not run and was explicitly removed from P2 completion scope by the user on 2026-07-18. It was restored disabled and no VoiceOver claim is made. The installed disclosure keyboard/AX check passed: Return expands and Space collapses while the AX value, hint, and child presence update. This result applies only to the tested disclosure control and does not certify full-app VoiceOver, rotor order, complete keyboard traversal, or every focused-control AX state.

The evidence manifest is [evidence/p2-ui-refinement-2026-07-17/README.md](evidence/p2-ui-refinement-2026-07-17/README.md).

## Implemented UI decisions

| Surface | P2 decision | Deterministic boundary |
| --- | --- | --- |
| Empty tray | A pristine empty/idle tray exposes one labelled **Capture Current Settings** primary button in the body and removes the duplicate header Capture icon. Nonempty or non-idle states retain one compact header Capture action. The help text states that Capture reads settings without changing the Mac. | Placement policy covers pristine empty, profile-present, running, success, partial, failure, prior-summary, and handoff-error states and requires exactly one visible Capture action. Capture itself is never invoked by the evidence fixture. |
| Profile actions | **New Profile** remains the single direct management action. Duplicate/Delete, Move Up/Down, and Import/Export are grouped in one labelled **More Profile Actions** menu, keeping the ordinary edit path visually quiet. | Policy tests fix the primary action and three secondary groups. Existing disabled-state checks still depend on selection, ordering, profile count, and mutation lock. |
| Dirty Export | The action is named **Export Saved Profiles…**. A dirty editor shows a persistent notice that Export uses saved profiles only and excludes unsaved changes. Export reads `ProfileStore.currentDocument()` and never merges editor draft state. | A temporary-store test edits a dirty draft, exports, imports the resulting JSON, and proves the saved name is exported while the unsaved name remains only in the editor. |
| Inclusion | Every setting uses the visible label **Apply with profile**, plus **Included** or **Not included** text and a non-color symbol. Its accessibility label includes the setting name; value and hint describe whether Apply changes that setting. | Presentation-policy tests cover both states, English semantics, accessibility copy, non-color symbols, and the accessibility-text stacked layout. |
| Disclosure | App-owned `AccessibleDisclosureGroup` uses a keyboard-activatable button, explicit localized Expanded/Collapsed value, next-action hint, stable identifier, and state owned by the containing screen. Collapsed content is absent from the accessibility tree. | Installed Return/Space activation and AX value/hint/child presence passed. VoiceOver was not run and is explicitly nonblocking for this P2 scope. |
| Advanced Diagnostics | The prior 700-point minimum is replaced by a 520×360 minimum and 640×460 ideal, both contained by the 680×480 Settings minimum. Header/actions and diagnostics rows adapt or stack at accessibility text sizes. | Geometry policy and a 680×480 Korean accessibility-text fixture cover containment and long-copy layout. This is not permission to clear diagnostics or mutate any system setting. |
| About, safety, result, and error | About links reflow vertically when required. Protected-change safety, result detail, and workflow error bodies scroll above stable safe action areas; heading accessibility-focus intent and safe Cancel/Revert/Close keyboard intent remain explicit. | Direct 520×360 Korean accessibility-text fixtures cover About, protected safety, long failed/rollback result, and long workflow error; a 680×480 Settings/About fixture covers the real Settings minimum. Synthetic focus intent does not prove actual focus. |
| Settings command | Every `⌘,`/Settings presentation synchronously routes to Profiles through one `routeToDefaultTab` transition. A hidden window starts a new presentation; an already-visible window changes tabs without resetting its presentation generation; a stale asynchronous completion cannot restore System or About. | Deterministic visible, close→reopen, and out-of-order-completion cases cover the routing contract. |
| Storage failures | Generic profile-store failures are promoted from a low-contrast footer line to a bordered, icon-and-heading error card. While the global recovery owns the surface, the profile workspace is disabled and stale editor feedback is cleared. Initial load failure offers one real Retry Loading action; ordinary operation failure offers one Dismiss Error action. Editor-owned save errors suppress a duplicate global card/footer error. | Temporary-store failure tests cover workspace/error ownership, retry/dismiss action ownership, repeated failed retry, and a single editor-owned save failure. No profile-store path-hardening claim is added. |

## Simple end-to-end flow

1. With no profile, the tray offers one clear **Capture Current Settings** entry point.
2. With profiles, users select **Review** or **Edit**; infrequent file/order/destructive operations live in one secondary menu.
3. Editing a value makes both its inclusion meaning and saved/draft boundary visible. Export always means the last saved profile document.
4. Review, protected confirmation, result, and error surfaces preserve one scrollable information area and one stable safe action area at the supported minimum.
5. Settings always opens on Profiles; diagnostics remain an on-demand troubleshooting surface inside the Settings size contract.

## Evidence and safety boundary

The ordinary integrated gate is non-live. It may build, render synthetic fixtures, package, checksum, mount read-only, and inspect signatures/resources, but it must not perform public-action Capture/Apply, UI automation against System Settings, TCC changes, login-item changes, Keychain writes, or hardware mutation.

The installed check was intentionally bounded to opening/closing and inspecting the changed app-owned surfaces. The named disclosure was exercised with ordinary Return/Space activation and its AX value, hint, and child presence were observed. VoiceOver was not run; the user explicitly removed it from this completion scope on 2026-07-18, and it was restored disabled. This is a narrow control-level keyboard/AX observation, not a full accessibility certification.

No display, ColorSync, audio, Ethernet/Wi-Fi IPv4, mouse, or keyboard preference is changed in this audit. No Capture or Apply Profile confirmation is activated. TCC, login, Gatekeeper, physical Intel, push/CI, Developer ID signing, notarization, and publication remain outside this local goal.

## Final verification ledger

| Item | Result |
| --- | --- |
| Integrated `make verify` | 461 checks |
| XCTest | 144 cases |
| Swift Testing | 316 cases across 39 suites |
| Isolated native popover regression | 1 |
| Universal no-Developer-ID DMG SHA-256 | `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031` |
| Reinstalled executable SHA-256 | `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719` |
| Synthetic evidence review | 39 fixtures and 79 artifacts generated and inspected: 15 tray, 13 Settings, three apply-preview, two responsive-workflow, and six auxiliary fixtures, plus one Settings footer comparison note |
| Installed changed-surface check | Pass: final DMG reinstalled; `⌘,` routes Profiles from visible System/About and close→reopen/stale cases; bounded disclosure keyboard/AX passes; no Apply/Capture/TCC/login/hardware mutation |
| Actual disclosure VoiceOver check | Not run; explicitly removed from P2 completion scope by the user on 2026-07-18, restored disabled, and no VoiceOver claim is made |
| Actual disclosure keyboard check | Pass: installed disclosure Return expands and Space collapses with AX value/hint/child presence updated |
| Apply/Capture/TCC/login/hardware mutation | Not run |
| Push, CI, tag, notarization, publication | Not run |
