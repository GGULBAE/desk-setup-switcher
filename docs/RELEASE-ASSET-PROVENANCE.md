# Release asset provenance

This record covers the static public-site media prepared for the Desk Setup
Switcher v0.1.0 public-beta candidate. The assets are derived from checked-in
DEBUG-only synthetic UI fixtures. No installed personal profile, live Capture,
Apply, permission request, UI automation, or display/audio/network mutation was
used to create them.

Capture, Edit, and Review were regenerated on 2026-07-20 from the exact
committed application-source tree
`f27c3f285d21b454cbd7326f704c45f29023048c` (`Harden release storage and
history audit`). Three filtered DEBUG-only offscreen evidence tests passed: one
selected English empty-tray fixture, one selected English Display-editor
fixture, and the three English/Korean Apply Preview fixtures. The evidence
write paths were enabled only for those runs.

All fixture models use deterministic synthetic identities, an isolated
temporary profile store, no system snapshot adapters, and a confirmation
closure that performs no action. The logical-size PNGs were visually inspected,
normalized, and stripped of host ICC and ancillary metadata before being
retained with their AX records under
`docs/evidence/public-release-assets/f27c3f2/`. The AX records reject concrete
`/Users/` paths and password text; the retained source set also passed the
release audit's credential, path, private-network, and device-identity scan.
These properties establish the data-source boundary; they do not prove
installed-window behavior, real hardware support, Apply, or rollback.

## Exact evidence generation record

The renderer host was an Apple M5 Mac running macOS 26.5.2 (`25F84`). Xcode
26.6 (`17F113`) was installed; the active `swift` driver reported Apple Swift
6.3.3. The attached offscreen AppKit/SwiftUI windows were never ordered front.
Their Retina backing scale produced raw 2× PNGs: `736×520` Capture, `1800×1136`
Edit, `1240×1000` standard Review, and `1040×720` minimum Review. Those raw
files retained host Display P3 or sRGB profiles and were not committed.

From a clean checkout whose `HEAD` equals the recorded source commit, the three
DEBUG test invocations were:

```sh
test "$(git rev-parse HEAD)" = "f27c3f285d21b454cbd7326f704c45f29023048c"

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
| `site/public/screenshots/capture.png` | `docs/evidence/public-release-assets/f27c3f2/capture/01-empty-en-light.png` (`6622e3331e9a712cbfdcc1bcceb2d80b43d832226b866227e1e8f30c37b4016e`), flattened over white and normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `5907d8427859093407373d0fa9bf6959a85d81baa7fc0f4a9a2c630f9531fcd5` | English light empty state, `368×260`, 17,830 bytes. Shows one centered Capture entry point; Capture was not invoked. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/screenshots/edit.png` | `docs/evidence/public-release-assets/f27c3f2/edit/13-display-en-light.png` (`5010e59ae841678c1b39bca716b1a734dfe2d8c9f76cff8cba005ec159e74ec8`), normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `5010e59ae841678c1b39bca716b1a734dfe2d8c9f76cff8cba005ec159e74ec8` | English light synthetic Display editor, `900×568`, 83,772 bytes. The footer identifies synthetic UI-audit mode; no save or hardware catalog operation occurred. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/screenshots/review.png` | `docs/evidence/public-release-assets/f27c3f2/review/23-apply-preview-en-initial.png` (`c31ba7e9d5543843297e87f1abdd76d65bbbd81b3d9d4420470c786d660e71d9`), flattened over white and normalized to opaque RGB24 by `scripts/build-public-demo.sh`, then stripped to critical PNG chunks | `6e01331fbb47099c383f501bdc2a0455f178375cf0746d34bd4b628feb0cd2cc` | English light initial normal Apply Preview, `620×500`, 85,018 bytes. The warning promises a restoration attempt, not a guarantee. Planned values are hard-coded test data and the confirmation closure performs no action. Apply and rollback were not run. No embedded ICC, textual, ancillary, or host-identifying metadata remains. |
| `site/public/demo/desk-setup-switcher.mp4` | The three normalized public screenshots, composed by `scripts/build-public-demo.sh` in Capture → Edit → Review order with two 0.6-second FFmpeg fades; H.264, `1280×720`, `yuv420p`, 37 seconds, input metadata excluded | `3f0e676d713842be7948fe002a9384c0df98a118dc1c422f882daa5a5815e094` | 467,726-byte silent synthetic product tour. It does not animate a click, claim successful Apply, or simulate hardware effects. The Review frame remains visible at the end. Standard MP4 brand, handler, and FFmpeg encoder tags remain; no source path, device, network, or personal metadata is present. |
| `site/public/demo/captions.en.vtt` | Original English caption copy written for the 37-second synthetic tour | `467bb3f0c453709fd38398b3ea9a7ef7451abb872734be6e691215c2309a27b5` | Five contiguous WebVTT cues from `00:00.000` through `00:37.000`; calls the artifact a public-beta candidate and keeps Apply a separate confirmation. |
| `site/public/demo/captions.ko.vtt` | Original Korean caption copy written for the same 37-second synthetic tour | `c43c6be5cc894cb4ea6de48695a0382b22b991b24896def62a99bffe427cc1b9` | Five contiguous WebVTT cues matching the English timing and verification boundary. |
| `site/public/og.png` | `docs/evidence/public-release-assets/og-background-imagegen.png` (`ee29d142b55020ca65fd7196ed3bb2c8a861111bab94ffe30fd3b2a330b6f543`), exact public icon, regenerated Edit screenshot, and evergreen English copy composed at `1280×640` by `scripts/build-social-preview.swift`, then normalized to opaque RGB24 and stripped to critical PNG chunks | `48267a74bc5b72a0d6843f3fb9967fd74da6df11717d0fc3b9874936811d509e` | The abstract background was produced with OpenAI image generation and contains no person, place, device, logo, or factual scene. The final 556,664-byte composition was visually inspected and has no embedded profile or ancillary metadata. |

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

The first script defaults to the evidence directory pinned to `f27c3f2`. The
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
accessibility. On 2026-07-20, the three public screenshots and social preview
were visually compared with their named sources at original resolution; the
Capture content was centered, Edit remained coherent without unintended
clipping, and Review exposed its warning, changes, and actions. English and
Korean AX records were retained, but full VoiceOver certification is excluded
from the initial public-beta gate and is not claimed.
