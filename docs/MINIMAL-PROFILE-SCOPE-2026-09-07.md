# Minimal profile scope — 2026-09-07

> [!NOTE]
> This is the historical six-setting milestone. The [2026-09-08 output-mute follow-up](OUTPUT-MUTE-2026-09-08.md) supersedes its mute-retirement statements; the current profile surface has seven Display/Sound settings and no per-setting inclusion switches.

## Contract

Capture, profile editing, and Apply share exactly six setting kinds: main display, per-display resolution, output device, output volume, input device, and input volume. Normal width retains the existing numbered Display/Sound rail; minimum/accessibility layouts retain the segmented fallback. Every option is direct. There is no Network or Advanced section, and App Settings no longer shows Wi-Fi capture permission controls.

The default profile snapshot uses only Display/Audio adapters and never requests Location access. Existing independent readiness/diagnostics readers may still discover local network facts; they do not add network values to a captured profile. New display captures do not store a refresh preference, mirror/arrangement/rotation/active-state request, or ICC option. New audio captures do not store system-output or mute options. Runtime device catalogs and complete transaction preflight/rollback state remain internal implementation evidence.

Legacy JSON values are preserved but normalization excludes retired leaves before editing, persistence, and planning. This also applies in Force mode. Resolution ignores legacy stored refresh rate: it uses a supported mode at the current session rate (existing 0.1 Hz nominal-rate tolerance) or produces a nonfatal omission. Primary-display changes may translate desktop origins as required by macOS; arbitrary arrangement and mirroring remain unchanged.

## Verification

Implementation commit: `a21b4ed` (local only; no push or new CI run).

Full canonical `make verify` passed, including lint/localization, default tests, the isolated native popover regression, release-tooling safety mocks, Swift/Xcode Debug and Release, Analyze, DMG creation, and mounted checksum/metadata/resources/architecture/signature verification. Logs: `.build/minimal-profile-verify.log` and `.build/minimal-profile-ui.log`. The default suite completed 195 XCTest cases (five opt-in skips) and 341 Swift Testing cases in 39 suites (two opt-in skips), plus the separately isolated native popover regression. Deterministic regression coverage includes the six-kind registry, legacy normal/Force no-op and round trip, capture without Location permission, snapshot allowlists, resolution/rate preservation and unsupported-rate omission, and full mock rollback. The 19-fixture English/Korean offscreen matrix passed in 106 seconds and exported 19 PNGs plus metadata into `.build/minimal-profile-ui-2026-09-07/`. Eleven representative PNGs were visually inspected, covering basic Display/Sound, full resolution/four-audio cards, unavailable volume, dark/minimum/accessibility text, validation, legacy-Network fallback, and App Settings. Standard-width rail pixels and layout/opacity/bounds assertions pass. These are synthetic offscreen views, not an installed interaction or VoiceOver walkthrough.

No live display, audio, network, input, permission, login-item, or third-party configuration mutation is authorized or performed by development checks. Installed keyboard/VoiceOver and physical Apply/rollback are not claimed. Existing unrelated Apply Preview edits are preserved and excluded from this milestone's commit.

## Authorized local installation

- Installed and launched `/Applications/Desk Setup Switcher.app`, version `0.0.9` / build `1`, after a normal quit. No draft was discarded or force quit used.
- DMG SHA-256: `1724f88bc4e1d48af0d22af848e6f2c60a2acb476b9234005af7799f30bfd048`.
- Mounted/installed ad-hoc-signed executable SHA-256: `b0433cd894d6b7f0545cd7f21a060774632e4c73baadbeb24b71f6537800e078`.
- Unsigned build executable SHA-256: `f0dc7a75f9960941c83669aa7b28eeb5e44e234d0e0f3a4f81b811c5fab87464`; the package copy's signature accounts for its different digest.
- Exact `arm64+x86_64`, strict code-signature verification, and the running installed path were checked. The DMG was detached.
- Private recovery directory: `.build/installed-app-minimal-20260907.cXOcgI/` (0700), containing `Previous.app`, both pre-install profile files (0600), and `RESTORE.md`.
- Both primary and backup profile files passed a value-free comparison: profile IDs/order/values/metadata remain intact after expected applicability normalization, with a sub-microsecond date tolerance for JSON encoding. Retired fields are excluded. This is not a byte-identical-file claim because inclusion flags intentionally changed.
- No hardware settings, permissions, login items, cloud state, GitHub publication, or third-party configuration were changed. The package includes the pre-existing local Apply Preview edits; those unrelated edits are not included in this milestone's commit.

## Next verification

After the non-live gate, check the installed two-section editor with normal user keyboard/scrolling at standard and minimum window sizes, without pressing Apply or changing system permissions. Record any issue and keep README/support status current. Hardware mutation needs its own explicit opt-in, preflight snapshot, interactive confirmation, and rollback plan.
