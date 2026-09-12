#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${1:-$ROOT_DIR/docs/evidence/public-release-assets/4ecdf48}"
SOURCE_CAPTURE="$SOURCE_ROOT/capture/01-empty-en-light.png"
SOURCE_EDIT_DISPLAY="$SOURCE_ROOT/edit/13-display-en-light.png"
SOURCE_EDIT_SOUND="$SOURCE_ROOT/sound/15-audio-en-dark.png"
SOURCE_REVIEW="$SOURCE_ROOT/review/27-launch-review-en-light.png"
PUBLIC_DIR="${2:-$ROOT_DIR/site/public}"
CAPTURE_OUTPUT="$PUBLIC_DIR/screenshots/capture.png"
EDIT_OUTPUT="$PUBLIC_DIR/screenshots/edit.png"
SOUND_OUTPUT="$PUBLIC_DIR/screenshots/sound.png"
REVIEW_OUTPUT="$PUBLIC_DIR/screenshots/review.png"
GALLERY_OUTPUT_DIR="$PUBLIC_DIR/gallery"
VIDEO_OUTPUT="$PUBLIC_DIR/demo/desk-setup-switcher.mp4"

fail() {
    echo "Public demo build failed: $*" >&2
    exit 1
}

for command_name in ffmpeg install sips swift; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command is unavailable: $command_name"
done

for source_path in \
    "$SOURCE_CAPTURE" \
    "$SOURCE_EDIT_DISPLAY" \
    "$SOURCE_EDIT_SOUND" \
    "$SOURCE_REVIEW"; do
    [[ -f "$source_path" ]] || fail "missing synthetic source fixture: $source_path"
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

mkdir -p \
    "$TEMP_DIR/screenshots" \
    "$TEMP_DIR/gallery-alpha" \
    "$TEMP_DIR/gallery-rgb" \
    "$TEMP_DIR/gallery" \
    "$TEMP_DIR/demo"

normalize_screenshot() {
    local source_path="$1"
    local width="$2"
    local height="$3"
    local output_path="$4"
    local temporary_path="$TEMP_DIR/$(basename "$output_path").rgb.png"

    # Flatten every offscreen fixture over white so the public derivative is
    # opaque, profile-free RGB even when the source uses transparent AppKit
    # window corners. The exact UI pixels themselves are never redrawn.
    ffmpeg -hide_banner -loglevel error -y \
        -i "$source_path" \
        -filter_complex \
        "color=c=white:s=${width}x${height}:r=1[background];[background][0:v]overlay=shortest=1:format=auto,format=rgb24" \
        -frames:v 1 \
        -map_metadata -1 \
        "$temporary_path"
    swift "$ROOT_DIR/scripts/strip-png-metadata.swift" \
        "$temporary_path" \
        "$output_path"
}

normalize_screenshot "$SOURCE_CAPTURE" 368 260 "$TEMP_DIR/screenshots/capture.png"
normalize_screenshot "$SOURCE_EDIT_DISPLAY" 900 568 "$TEMP_DIR/screenshots/edit.png"
normalize_screenshot "$SOURCE_EDIT_SOUND" 900 568 "$TEMP_DIR/screenshots/sound.png"
normalize_screenshot "$SOURCE_REVIEW" 620 440 "$TEMP_DIR/screenshots/review.png"

# Marketing cards add only deterministic project copy and framing around the
# exact normalized fixtures. They never simulate clicks, Apply success, or a
# live hardware result.
sips -s format png "$ROOT_DIR/site/public/app-icon.svg" \
    --out "$TEMP_DIR/app-icon.png" >/dev/null
swift "$ROOT_DIR/scripts/build-launch-gallery.swift" \
    "$TEMP_DIR/app-icon.png" \
    "$TEMP_DIR/screenshots/capture.png" \
    "$TEMP_DIR/screenshots/edit.png" \
    "$TEMP_DIR/screenshots/sound.png" \
    "$TEMP_DIR/screenshots/review.png" \
    "$TEMP_DIR/gallery-alpha"

gallery_names=(
    "01-capture.png"
    "02-edit-display.png"
    "03-edit-sound.png"
    "04-review.png"
)
for gallery_name in "${gallery_names[@]}"; do
    ffmpeg -hide_banner -loglevel error -y \
        -i "$TEMP_DIR/gallery-alpha/$gallery_name" \
        -vf format=rgb24 \
        -frames:v 1 \
        -map_metadata -1 \
        "$TEMP_DIR/gallery-rgb/$gallery_name"
    swift "$ROOT_DIR/scripts/strip-png-metadata.swift" \
        "$TEMP_DIR/gallery-rgb/$gallery_name" \
        "$TEMP_DIR/gallery/$gallery_name"
done

# The four cards remain static long enough to read, with restrained fades. The
# 40-second H.264 output is deliberately silent and ends at Review; it never
# invokes or depicts a successful Apply or any live setting mutation.
ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -t 10.6 -i "$TEMP_DIR/gallery/01-capture.png" \
    -loop 1 -framerate 30 -t 8.6 -i "$TEMP_DIR/gallery/02-edit-display.png" \
    -loop 1 -framerate 30 -t 8.6 -i "$TEMP_DIR/gallery/03-edit-sound.png" \
    -loop 1 -framerate 30 -t 14.0 -i "$TEMP_DIR/gallery/04-review.png" \
    -filter_complex \
    "[0:v]scale=1280:720:flags=lanczos:force_original_aspect_ratio=increase,crop=1280:720,setsar=1[capture];\
[1:v]scale=1280:720:flags=lanczos:force_original_aspect_ratio=increase,crop=1280:720,setsar=1[display];\
[2:v]scale=1280:720:flags=lanczos:force_original_aspect_ratio=increase,crop=1280:720,setsar=1[sound];\
[3:v]scale=1280:720:flags=lanczos:force_original_aspect_ratio=increase,crop=1280:720,setsar=1[review];\
[capture][display]xfade=transition=fade:duration=0.6:offset=10.0[capture-display];\
[capture-display][sound]xfade=transition=fade:duration=0.6:offset=18.0[capture-display-sound];\
[capture-display-sound][review]xfade=transition=fade:duration=0.6:offset=26.0,format=yuv420p,setparams=colorspace=bt709:color_primaries=bt709:color_trc=bt709[video]" \
    -map "[video]" \
    -an \
    -t 40 \
    -r 30 \
    -c:v libx264 \
    -crf 18 \
    -preset slow \
    -tune stillimage \
    -pix_fmt yuv420p \
    -colorspace bt709 \
    -color_primaries bt709 \
    -color_trc bt709 \
    -force_key_frames "0,4,10,18,26,36" \
    -fflags +bitexact \
    -flags:v +bitexact \
    -threads 1 \
    -movflags +faststart \
    -map_metadata -1 \
    "$TEMP_DIR/demo/desk-setup-switcher.mp4"

mkdir -p "$PUBLIC_DIR/screenshots" "$GALLERY_OUTPUT_DIR" "$PUBLIC_DIR/demo"
install -m 0644 "$TEMP_DIR/screenshots/capture.png" "$CAPTURE_OUTPUT"
install -m 0644 "$TEMP_DIR/screenshots/edit.png" "$EDIT_OUTPUT"
install -m 0644 "$TEMP_DIR/screenshots/sound.png" "$SOUND_OUTPUT"
install -m 0644 "$TEMP_DIR/screenshots/review.png" "$REVIEW_OUTPUT"
for gallery_name in "${gallery_names[@]}"; do
    install -m 0644 \
        "$TEMP_DIR/gallery/$gallery_name" \
        "$GALLERY_OUTPUT_DIR/$gallery_name"
done
install -m 0644 "$TEMP_DIR/demo/desk-setup-switcher.mp4" "$VIDEO_OUTPUT"

echo "Built public Capture, Edit Display, Edit Sound, and Review gallery plus silent demo."
