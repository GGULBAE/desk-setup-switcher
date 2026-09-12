# Release asset provenance

Last verified: 2026-09-12

This record covers the repository and bilingual holding-site media prepared for
Desk Setup Switcher. Every product screen comes from checked-in DEBUG-only
synthetic UI fixtures. No installed personal profile, live Capture, permission
request, Apply, UI automation, or display/audio/network mutation was used.

The current Capture, Edit Display, Edit Sound, and Review evidence was generated
from a clean detached checkout of exact application-source commit
`4ecdf48a712fe1bee1142d00dc56403adc5caf0a` (`Add current-scope launch review
fixture`). The resulting gallery demonstrates the current seven-setting
Display/Sound scope and manual workflow. It is product-tour evidence, not proof
of a supported download, installed-window behavior, or hardware mutation.

## Source boundary

The offscreen fixture models use deterministic synthetic identities, an
isolated temporary profile store, and no live system snapshot adapters. The
Review renderer's confirmation closure records a test failure if invoked, its
window is never ordered front, and its retained AX record declares
`live-system-mutations=false`. The Capture and editor fixtures retain their own
read-only AX boundary records.

The run used an Apple M5 Mac on macOS 26.6.2 (`25G83`), Xcode 26.6 (`17F113`),
Apple Swift 6.3.3, and FFmpeg/ffprobe 9.0.1. AppKit produced Retina raw frames at
`736×520`, `1800×1136`, `1800×1136`, and `1240×880`. FFmpeg Lanczos-scaled those
frames to their logical sizes, forced opaque RGB24, excluded input metadata, and
`scripts/strip-png-metadata.swift` retained only critical PNG chunks.

From the exact clean checkout, the gated generation commands were:

```sh
test "$(git rev-parse HEAD)" = "4ecdf48a712fe1bee1142d00dc56403adc5caf0a"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DESK_SETUP_WRITE_TRAY_EVIDENCE=1 \
DESK_SETUP_TRAY_EVIDENCE_DIR="$RAW_ROOT/capture" \
DESK_SETUP_TRAY_EVIDENCE_FIXTURE=01-empty-en-light \
swift test --filter TrayOffscreenEvidenceTests.rendersSyntheticMatrix \
  -Xswiftc -warnings-as-errors

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 \
DESK_SETUP_REFINEMENT_EVIDENCE_DIR="$RAW_ROOT/edit" \
DESK_SETUP_REFINEMENT_EVIDENCE_FIXTURE=13-display-en-light \
swift test --filter TrayOffscreenEvidenceTests.rendersSimplifiedProfileSections \
  -Xswiftc -warnings-as-errors

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DESK_SETUP_WRITE_REFINEMENT_EVIDENCE=1 \
DESK_SETUP_REFINEMENT_EVIDENCE_DIR="$RAW_ROOT/sound" \
DESK_SETUP_REFINEMENT_EVIDENCE_FIXTURE=15-audio-en-dark \
swift test --filter TrayOffscreenEvidenceTests.rendersSimplifiedProfileSections \
  -Xswiftc -warnings-as-errors

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
DESK_SETUP_WRITE_LAUNCH_GALLERY_EVIDENCE=1 \
DESK_SETUP_LAUNCH_GALLERY_EVIDENCE_DIR="$RAW_ROOT/review" \
swift test --filter LaunchGalleryEvidenceTests.rendersCurrentScopeReview \
  -Xswiftc -warnings-as-errors
```

The four selected tests passed. Their logical-size PNG and AX outputs are
retained under `docs/evidence/public-release-assets/4ecdf48/`. Normalization can
be reproduced by scaling each raw PNG to the size below with FFmpeg
`scale=WIDTH:HEIGHT:flags=lanczos,format=rgb24`, setting `-map_metadata -1`, and
then running `scripts/strip-png-metadata.swift`.

| Retained source | Size | SHA-256 |
| --- | ---: | --- |
| `capture/01-empty-en-light.ax.txt` | 1,147 bytes | `b6fda0fcfc7c470e4a352a564e3df5c1c60181b3cb31c09c5e6ae3b08a48856c` |
| `capture/01-empty-en-light.png` | `368×260`, 17,438 bytes | `fbfa2b1520c06c768fc6de7f8ce2d2345f28000a91647ba05d7fe924f7fe10db` |
| `edit/13-display-en-light.ax.txt` | 1,304 bytes | `57548989a23148f3f7f7781263d5ceb4b96aae4a5f704e5be184811c7c60d4d5` |
| `edit/13-display-en-light.png` | `900×568`, 84,620 bytes | `5462adeae1a0a7b2ccb5c15e34f43b99dacacbad91f1c5e5946b17159dc4ee87` |
| `sound/15-audio-en-dark.ax.txt` | 1,304 bytes | `a9e3625790f95a1460a572e49aa472d8d61fefe8d00f1ebd9d0b9af721ba195d` |
| `sound/15-audio-en-dark.png` | `900×568`, 87,776 bytes | `0c66205d06dc39e3667ae49f16dc490b792c7f7740e3482cb5a008ff0e3ad585` |
| `review/27-launch-review-en-light.ax.txt` | 411 bytes | `c9cc1e08efe105fab6086cdfacb6e7e153774c5aa7d322dff7bffc1824a40b2b` |
| `review/27-launch-review-en-light.png` | `620×440`, 37,156 bytes | `2a1ca3014e499ee2b74f50d175af9712ff7c69fa74fefcbe6f12d4770ff6d1f1` |
| `og-background-imagegen.png` | 1,307,060 bytes | `ee29d142b55020ca65fd7196ed3bb2c8a861111bab94ffe30fd3b2a330b6f543` |

`docs/evidence/public-release-assets/sources.sha256` is the authoritative exact
manifest for this nine-file tree.

## Public derivatives

`scripts/build-public-demo.sh` copies the four normalized source frames into the
public screenshot set, then calls `scripts/build-launch-gallery.swift`. The
AppKit builder adds only original project copy, the exact app icon, background
geometry, and framing around those exact frames; it does not redraw product UI.
The four `1270×760` cards are composed into a silent 40-second H.264 tour with
three 0.6-second fades. The tour ends on Review and never depicts an Apply click,
success state, or hardware effect. Two consecutive builds produced byte-identical
screenshots, cards, and video.

| Public asset | Purpose and boundary | SHA-256 |
| --- | --- | --- |
| `app-icon.svg` | Exact copy of original project artwork in `Assets/AppIcon.svg` | `c183b584887cd946d0d0a4d3b1da77749ef4016ea6886c7ef798b7339aa1d109` |
| `screenshots/capture.png` | Opaque `368×260` synthetic empty tray; Capture not invoked | `fbfa2b1520c06c768fc6de7f8ce2d2345f28000a91647ba05d7fe924f7fe10db` |
| `screenshots/edit.png` | Opaque `900×568` synthetic Display editor; nothing saved | `5462adeae1a0a7b2ccb5c15e34f43b99dacacbad91f1c5e5946b17159dc4ee87` |
| `screenshots/sound.png` | Opaque `900×568` synthetic Sound editor; no microphone recording | `0c66205d06dc39e3667ae49f16dc490b792c7f7740e3482cb5a008ff0e3ad585` |
| `screenshots/review.png` | Opaque `620×440` two-change Review; confirmation not invoked | `2a1ca3014e499ee2b74f50d175af9712ff7c69fa74fefcbe6f12d4770ff6d1f1` |
| `gallery/01-capture.png` | `1270×760` Capture card | `d72896a7ef4e4ac84854c380268c87438c934254b834712350c929825fb3691c` |
| `gallery/02-edit-display.png` | `1270×760` Display card | `bd1441e159222f694c3de13751cb0369b7dea4676d9c5d0e3be7534f1942627a` |
| `gallery/03-edit-sound.png` | `1270×760` Sound card | `338c5df1cd6789aae5ff1fbb6666394b1ffb5786e371b02520997b2ff1b7b5b7` |
| `gallery/04-review.png` | `1270×760` Review card; explicitly says profiles never auto-switch | `554565f778857b5296718ea7cb1fe07bb2aef31b8217bedb5f9740240e54d663` |
| `demo/desk-setup-switcher.mp4` | 1,594,353-byte H.264, `1280×720`, 30 fps, BT.709, `yuv420p`, no audio, exactly 40 seconds | `5b42fe0596337183a1323c7866b925339d3abf6cbeefad431e7dd32b5fda369b` |
| `demo/captions.en.vtt` | Six English cues spanning `00:00.000`–`00:40.000` | `b6f40d1176523ef6dbb1f45da610188b1efecc78e8d466e1c59c132d83c550a2` |
| `demo/captions.ko.vtt` | Six Korean cues on the same exact timeline | `1341844ccb0a453b876320777cc9d864b00bac61b4d8d71b4fd77f84c62fcce3` |
| `og.png` | `1280×640` social card using the exact current Capture frame and generated abstract background | `2e3363394a8e658f8016fd06aa5c5ac268123f0934b00b2ede08135aa0063375` |

`site/public/assets.sha256` is the authoritative 13-file public manifest. Every
public PNG is opaque, has no embedded ICC profile, and contains only critical
PNG chunks. The MP4 retains ordinary container/codec fields and is not described
as metadata-free.

## Social-preview background

The abstract social-preview background is the only image-generation output in
this asset set. Product UI, gallery artwork, iconography, and typography were not
image-generated. The retained prompt was:

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

The generated source contains no person, place, device, logo, or factual scene.

## Licensing

The app icon, synthetic fixture data, gallery copy and composition, caption copy,
and interface artwork are project work distributed under the MIT License. The
abstract background is an OpenAI image-generation output commissioned by project
contributors and distributed under MIT to the extent permitted by applicable
law and terms. Product screenshots and the derived video include SF Symbols only
in context as part of the macOS interface; individual symbols are not
redistributed. No third-party logo, stock artwork, or personal-device screenshot
is included. See `docs/ASSET-LICENSES.md` for the ledger.

## Reproduction and verification

With the exact source evidence present, run:

```sh
scripts/build-public-demo.sh
scripts/build-social-preview.sh
make verify-public-assets
```

The verifier requires the exact source and public file trees and manifests. It
checks geometry, opacity, missing ICC profiles, critical-only PNG chunks, AX
fixture and no-mutation declarations, high-confidence secret/path/network/device
patterns, current Display/Sound scope copy, video streams and BT.709 properties,
and the exact bilingual six-cue timeline.

On 2026-09-12, the four retained source frames, four gallery cards, regenerated
social preview, and representative video frames at 2, 12, 20, 30, and 38 seconds
were visually inspected. The generated cards preserve all important controls and
copy without clipping. This review and the AX logs do not constitute OCR,
VoiceOver certification, installed focus evidence, or hardware verification.
