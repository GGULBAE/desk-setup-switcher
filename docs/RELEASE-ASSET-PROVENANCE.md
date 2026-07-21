# Release asset provenance

This record covers the static public-site media prepared for the Desk Setup
Switcher v0.1.0 public-beta candidate. The assets are derived from checked-in
DEBUG-only synthetic UI fixtures. No installed personal profile, live Capture,
Apply, permission request, UI automation, or display/audio/network mutation was
used to create them.

Capture, Edit, and Review were regenerated on 2026-07-21 from the exact
committed application-source tree
`bc3ec58e2f1f13e3c47be3e879fed957564012cd` (`Simplify and qualify Apply
Preview flow`). Three filtered DEBUG-only offscreen evidence tests passed: one
selected English empty-tray fixture, one selected English Display-editor
fixture, and the three English/Korean Apply Preview fixtures. The evidence
write paths were enabled only for those runs.

All fixture models use deterministic synthetic identities, an isolated
temporary profile store, no system snapshot adapters, and a confirmation
closure that performs no action. The logical-size PNGs were visually inspected,
normalized, and stripped of host ICC and ancillary metadata before being
retained with their AX records under
`docs/evidence/public-release-assets/bc3ec58/`. The AX records reject concrete
`/Users/` paths and password text; the retained source set also passed the
release audit's credential, path, private-network, and device-identity scan.
These properties establish the data-source boundary; they do not prove
installed-window behavior, real hardware support, Apply, or rollback.

## Exact evidence generation record

The renderer host was an Apple M5 Mac running macOS 26.5.2 (`25F84`). Xcode
26.6 (`17F113`) was installed; the active `swift` driver reported Apple Swift
6.3.3. The attached offscreen AppKit/SwiftUI windows were never ordered front.
The current offscreen renderer produced logical-size raw PNGs: `368×260`
Capture, `900×568` Edit, `620×500` standard Review, and `520×360` minimum
Review. Those raw files retained the host display or sRGB profile and were not
committed; normalization removed that metadata before promotion.

From a clean checkout whose `HEAD` equals the recorded source commit, the three
DEBUG test invocations were:

```sh
test "$(git rev-parse HEAD)" = "bc3ec58e2f1f13e3c47be3e879fed957564012cd"

DESK_SETUP_WRITE_TRAY_EVIDENCE=1 \
DESK_SETUP_TRAY_EVIDENCE_DIR="$RAW_ROOT/capture" \
DESK_SETUP_TRAY_EVIDENCE_FIXTURE=01-empty-en-light \
swift test --filter TrayOffscreenEvidenceTests.rendersSyntheticMatrix

DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 \
DESK_SETUP_REFINEMENT_EVIDENCE_DIR="$RAW_ROOT/edit" \
DESK_SETUP_REFINEMENT_EVIDENCE_FIXTURE=13-display-en-light \
swift test --filter TrayOffscreenEvidenceTests.rendersSimplifiedProfileSections

DESK_SETUP_WRITE_WORKFLOW_EVIDENCE=1 \
DESK_SETUP_WORKFLOW_EVIDENCE_DIR="$RAW_ROOT/review" \
swift test --filter TrayOffscreenEvidenceTests.rendersApplyPreviewStates
```

`RAW_ROOT` and `NORMALIZED_ROOT` were new temporary directories outside the
repository; the latter mirrored the retained `capture/`, `edit/`, and `review/`
layout. The following normalization function and invocations produced the
retained logical-size PNG bytes with FFmpeg 8.1.2:

```sh
normalize_fixture() {
    raw_path="$1"
    width="$2"
    height="$3"
    retained_path="$4"
    metadata_path="$RAW_ROOT/$(basename "$retained_path").normalized.png"

    ffmpeg -hide_banner -loglevel error -y \
        -i "$raw_path" \
        -vf "scale=${width}:${height}:flags=lanczos" \
        -frames:v 1 \
        -map_metadata -1 \
        "$metadata_path"
    swift scripts/strip-png-metadata.swift "$metadata_path" "$retained_path"
}

normalize_fixture "$RAW_ROOT/capture/01-empty-en-light.png" 368 260 \
    "$NORMALIZED_ROOT/capture/01-empty-en-light.png"
normalize_fixture "$RAW_ROOT/edit/13-display-en-light.png" 900 568 \
    "$NORMALIZED_ROOT/edit/13-display-en-light.png"
normalize_fixture "$RAW_ROOT/review/23-apply-preview-en-initial.png" 620 500 \
    "$NORMALIZED_ROOT/review/23-apply-preview-en-initial.png"
normalize_fixture "$RAW_ROOT/review/24-apply-preview-ko-refreshed.png" 620 500 \
    "$NORMALIZED_ROOT/review/24-apply-preview-ko-refreshed.png"
normalize_fixture "$RAW_ROOT/review/25-apply-preview-ko-minimum-large-text.png" 520 360 \
    "$NORMALIZED_ROOT/review/25-apply-preview-ko-minimum-large-text.png"

install -m 0644 "$RAW_ROOT/capture/01-empty-en-light.ax.txt" \
    "$NORMALIZED_ROOT/capture/01-empty-en-light.ax.txt"
install -m 0644 "$RAW_ROOT/edit/13-display-en-light.ax.txt" \
    "$NORMALIZED_ROOT/edit/13-display-en-light.ax.txt"
install -m 0644 "$RAW_ROOT/review/"*.ax.txt "$NORMALIZED_ROOT/review/"
```

Replaying this normalization against the retained raw run reproduced all five
source PNG SHA-256 values in `sources.sha256` exactly.

## Asset manifest

| Public asset | Source and transformation | SHA-256 | Synthetic and verification boundary |
| --- | --- | --- | --- |
| `site/public/app-icon.svg` | Exact copy of `Assets/AppIcon.svg`; original project artwork | `c183b584887cd946d0d0a4d3b1da77749ef4016ea6886c7ef798b7339aa1d109` | Contains no third-party logo or device artwork. The verifier requires byte identity with the canonical SVG. |
| `site/public/screenshots/capture.png` | `docs/evidence/public-release-assets/bc3ec58/capture/01-empty-en-light.png` (`cf04f1b858ce7cf51130ba1c3c99432f0701ee0f856ecad979d017051c4a7309`), flattened over white and normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `b9cf538d3c45efccd2b42e3906af36a08a5ce83bba3561d1e7794d57b43190c9` | English light empty state, `368×260`, 12,827 bytes. Shows one centered Capture entry point; Capture was not invoked. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/screenshots/edit.png` | `docs/evidence/public-release-assets/bc3ec58/edit/13-display-en-light.png` (`26f736695bb78f0b90e32de9e210111fa9aa5178e23ba494f5f146936144e3f9`), normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `26f736695bb78f0b90e32de9e210111fa9aa5178e23ba494f5f146936144e3f9` | English light synthetic Display editor, `900×568`, 57,227 bytes. The footer identifies synthetic UI-audit mode; no save or hardware catalog operation occurred. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/screenshots/review.png` | `docs/evidence/public-release-assets/bc3ec58/review/23-apply-preview-en-initial.png` (`3611b34acef0bd311667cbd134fa62e76b19dbc4e751c27dd64ab2737d85ae0b`), flattened over white and normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `cf23a1c2a6080ff1bff1b64baa26cdd59aaa70ed232d852cd86216aae3b9351d` | English light initial normal Apply Preview, `620×500`, 55,817 bytes. The visible text-and-shield Beta status says Apply/rollback are not hardware-verified and asks users to check System Settings afterward. Review content precedes both decision actions; the confirmation closure performs no action. Apply and rollback were not run. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/demo/desk-setup-switcher.mp4` | The three normalized public screenshots, composed by `scripts/build-public-demo.sh` in Capture → Edit → Review order with two 0.6-second FFmpeg fades; H.264, `1280×720`, `yuv420p`, 37 seconds, input metadata excluded | `ef9ad94ce5b427d06b6d15de76f12cfd0f04dfc111287593146e6eb750c9e56c` | 482,638-byte silent synthetic product tour. It does not animate a click, claim successful Apply, or simulate hardware effects. The Review frame and Beta boundary remain visible at the end. Standard MP4 brand, handler, and FFmpeg encoder tags remain; no source path, device, network, or personal metadata is present. |
| `site/public/demo/captions.en.vtt` | Original English caption copy written for the 37-second synthetic tour | `360b36314ffda121597bc1c17af5139a84a0161f3ffa81a6fbccc12d9797a6e5` | Five contiguous WebVTT cues from `00:00.000` through `00:37.000`; calls the artifact a public-beta candidate, names the Beta hardware-verification boundary, keeps Apply separate, and asks users to check System Settings afterward. |
| `site/public/demo/captions.ko.vtt` | Original Korean caption copy written for the same 37-second synthetic tour | `ed5a31c48a782e67522a3f1c5144f436bfee287a0178b3f3c0983eb71ed445b4` | Five contiguous WebVTT cues matching the English timing and verification boundary. |
| `site/public/og.png` | `docs/evidence/public-release-assets/og-background-imagegen.png` (`ee29d142b55020ca65fd7196ed3bb2c8a861111bab94ffe30fd3b2a330b6f543`), exact public icon, regenerated Edit screenshot, and evergreen English copy composed at `1280×640` by `scripts/build-social-preview.swift`, then normalized to opaque RGB24 and stripped to critical PNG chunks | `6cff49e8e86e42f82e8b92a96f74af77c6609073a486a9ee43c0660b56b9adda` | The abstract background was produced with OpenAI image generation and contains no person, place, device, logo, or factual scene. The final 552,970-byte composition was visually inspected and has no embedded profile or ancillary metadata. |

The public PNG and video normalization was performed with FFmpeg 8.1.2. All
three screenshots and the video are current deterministic outputs of
`scripts/build-public-demo.sh`; the social preview is a current deterministic
output of `scripts/build-social-preview.sh`. `sips` reports the documented
dimensions, `hasAlpha: no`, and `profile: <nil>` for every public PNG. A chunk
walk found only `IHDR`, `IDAT`, and `IEND`; the metadata stripper deliberately
removes every ancillary chunk. The MP4 retains normal container/codec tags and
is not represented as zero metadata.

## Social-preview background prompt

The built-in OpenAI image-generation tool was called once for the background
layer. The generated bitmap was inspected before use, then copied into the
repository under the hash in the manifest. Product UI, iconography, and text
were not generated; the final card composites the exact public project assets
and deterministic AppKit typography over this background.

```text
Use case: ads-marketing
Asset type: background layer for a 1280×640 GitHub social preview card
Primary request: Create a refined, understated background for the open-source macOS utility “Desk Setup Switcher”.
Scene/backdrop: edge-to-edge deep navy-to-evergreen gradient with a very subtle blue-teal glow and restrained translucent frosted-glass arcs; no horizon or room.
Composition/framing: exact 2:1 landscape composition. Keep the left 55% calm and dark for later typography. Make the right 45% slightly brighter as a stage where an actual application screenshot will be composited later. Preserve generous safe margins.
Style/medium: premium native macOS launch artwork, crisp, minimal, quiet, trustworthy, not futuristic.
Color palette: midnight navy, charcoal, muted evergreen, restrained cyan-blue highlights.
Constraints: background layer only; no text, no letters, no UI, no app windows, no icons, no logos, no devices, no people, no mockups, no decorative particles, no watermark. Do not imitate or include third-party brands.
```

## Licensing

The app icon, fixture data, caption copy, composition, and original interface
artwork are project work distributed under the MIT License. The abstract social
preview background is an OpenAI image-generation output commissioned by the
project. Under the applicable [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/),
the requester owns the output as between the requester and OpenAI to the extent
permitted by law; the project distributes its rights in that output under MIT.
The generated source and its hash are retained so the origin is not represented
as human-made. Product screenshots and the derived video include SF Symbols
only in context as part of the macOS interface. They do not redistribute
individual symbols; Apple's applicable platform terms continue to govern those
embedded symbols. No third-party logo, stock artwork, or personal device
screenshot is included.

## Reproduction and verification

The release media must remain pinned to the source and derivative hashes above.
`site/public/assets.sha256` pins all eight public derivatives, while
`docs/evidence/public-release-assets/sources.sha256` pins the generated
background plus five exact-commit PNG/AX pairs: Capture, Edit, and three Review
states. The retained evidence was produced with explicitly gated output paths
from the exact source commit recorded above, normalized with FFmpeg, and
stripped with `scripts/strip-png-metadata.swift`. With that evidence present,
run:

```sh
scripts/build-public-demo.sh
scripts/build-social-preview.sh
make verify-public-assets
```

The first script defaults to the evidence directory pinned to `bc3ec58`. The
verifier requires `ffmpeg`, `ffprobe`, `ruby`, `sips`, `shasum`, and standard
macOS command-line tools. Missing media prerequisites are failures, not skipped
checks. It verifies exact geometry, expected alpha, absence of embedded ICC
profiles, and a critical-chunk-only structure with no trailing data for all
five retained source PNGs and all four public PNGs. It scans both source
evidence and public derivatives for high-confidence credential, personal-path,
private-network, and device-profile patterns; verifies the video format,
duration and absence of audio; and validates both caption timelines. Both
checksum manifests are mandatory, must contain exactly their declared files,
and are checked from their respective base directories.

This automated evidence does not OCR image pixels or certify complete
accessibility. On 2026-07-21, all five normalized source images were visually
compared side by side with the preceding pinned sources at matching viewports,
and the three public screenshots, social preview, and representative demo
frames were inspected. Capture remained centered, Edit remained coherent
without unintended clipping, standard Review exposed the Beta boundary,
warnings, changes, and actions, and minimum-size Korean large text began at the
top with the rest reachable through the tested scroll sequence. English and
Korean AX boundary records were retained; offscreen SwiftUI descendants may
remain collapsed into `AXGroup`, so complete focused-control observation and
full VoiceOver certification are not claimed.
