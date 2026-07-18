# P2 UI refinement evidence — 2026-07-17

This directory indexes the bounded evidence for [the P2 UI refinement audit](../../P2-UI-REFINEMENT-AUDIT-2026-07-17.md). The final manifest was generated and inspected: 39 visual fixtures produced 39 images and 39 same-basename AX companions, plus one Settings footer comparison note, for 79 artifacts. This index is not counted as an artifact.

## Evidence classes

| Class | Intended coverage | Final result |
| --- | --- | --- |
| Attached/offscreen synthetic | Empty tray in English/Korean; Settings at 680×480 with Korean accessibility text; About, protected safety, long result, workflow error at 520×360; diagnostics and Settings/About at 680×480 | Pass: 39 fixtures and 79 artifacts generated and inspected—15 tray, 13 Settings, three apply-preview, two responsive-workflow, and six auxiliary fixtures, plus one Settings footer comparison note |
| Installed app | Reinstalled package identity plus bounded inspection of the changed app-owned surfaces without Apply/Capture | Pass: final DMG reinstalled; `⌘,` routes Profiles from visible System/About and close→reopen/stale cases; bounded disclosure keyboard/AX passes; no Apply/Capture/TCC/login/hardware mutation |
| Disclosure accessibility | Label, Expanded/Collapsed value, next-action hint, collapsed-child absence, expanded-child presence, and Space/Return activation for the named disclosure control | VoiceOver: not run and explicitly removed from P2 completion scope by the user on 2026-07-18; restored disabled; no VoiceOver claim. Keyboard/AX: pass—Return expands and Space collapses with value/hint/child presence updated |
| Package | Universal architectures, resources, checksum, mounted layout, and ad-hoc/no-Developer-ID signature class | DMG SHA-256: `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`; installed executable SHA-256: `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719` |

## Synthetic fixture contract

Synthetic fixtures use injected data, a temporary profile store, disabled permission requests, and suppressed public actions. Korean `accessibility3` is a layout stress fixture, not proof that the host's real Accessibility display settings were changed. Offscreen AX notes describe the constructed tree and declared focus intent; they do not prove VoiceOver speech, rotor order, or first-responder state.

Final manifest:

- `tray/`: 15 fixtures, each with one PNG and one AX companion (30 artifacts).
- `settings/`: 13 fixtures, each with one PNG and one AX companion, plus `16b-16c-profile-footer-comparison.ax.txt` (27 artifacts).
- `apply-preview/`: three fixtures, each with one PNG and one AX companion (six artifacts).
- `workflow/`: two fixtures, each with one JPEG and one AX companion (four artifacts).
- `auxiliary/`: six fixtures, each with one JPEG and one AX companion (12 artifacts).

Total: 39 fixtures and 79 artifacts. All were generated and inspected.

## Installed and actual-assistive-technology boundary

The installed pass may open, resize, inspect, keyboard-activate the named disclosure, and close app-owned surfaces. It must retain a preflight/rollback record and must not activate Capture, Apply Profile, permission requests, login controls, diagnostics clearing, profile import/export, or any display/ColorSync/audio/network/input mutation.

The installed keyboard/AX record is intentionally control-scoped. Return expanded the named disclosure and Space collapsed it while AX value, hint, and child presence updated. VoiceOver was not run, was explicitly removed from P2 completion scope by the user on 2026-07-18, and was restored disabled. No VoiceOver claim is made, and this record cannot be generalized to a complete rotor, focus-order, or keyboard-only audit of the app.

## Final integrity record

- Integrated checks: 461 (144 XCTest + 316 Swift Testing across 39 suites + one isolated native popover regression)
- DMG SHA-256: `342d804d8bbff51209af4bccefb405ee76499050c1e640a011d41e2f78792031`
- Installed executable SHA-256: `fb35352fb6a9588c0c50269975ccd3d7b73e52010de10de132bf45d60236f719`
- Installed changed-surface result: pass—final DMG reinstalled; `⌘,` routes Profiles from visible System/About and close→reopen/stale cases; bounded disclosure keyboard/AX passes; no Apply/Capture/TCC/login/hardware mutation
- Disclosure VoiceOver result: not run; explicitly removed from P2 completion scope by the user on 2026-07-18; restored disabled; no VoiceOver claim
- Disclosure keyboard/AX result: pass—installed disclosure Return expands and Space collapses with AX value/hint/child presence updated
