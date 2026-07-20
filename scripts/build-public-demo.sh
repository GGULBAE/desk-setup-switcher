#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${1:-$ROOT_DIR/docs/evidence/public-release-assets/f27c3f2}"
SOURCE_CAPTURE="$SOURCE_ROOT/capture/01-empty-en-light.png"
SOURCE_EDIT="$SOURCE_ROOT/edit/13-display-en-light.png"
SOURCE_REVIEW="$SOURCE_ROOT/review/23-apply-preview-en-initial.png"
PUBLIC_DIR="$ROOT_DIR/site/public"
CAPTURE_OUTPUT="$PUBLIC_DIR/screenshots/capture.png"
EDIT_OUTPUT="$PUBLIC_DIR/screenshots/edit.png"
REVIEW_OUTPUT="$PUBLIC_DIR/screenshots/review.png"
VIDEO_OUTPUT="$PUBLIC_DIR/demo/desk-setup-switcher.mp4"

fail() {
    echo "Public demo build failed: $*" >&2
    exit 1
}

for command_name in ffmpeg swift; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command is unavailable: $command_name"
done

for source_path in "$SOURCE_CAPTURE" "$SOURCE_EDIT" "$SOURCE_REVIEW"; do
    [[ -f "$source_path" ]] || fail "missing synthetic source fixture: $source_path"
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Flatten the exact committed synthetic Capture source over white, retain the
# logical 368x260 canvas, and strip every ancillary PNG chunk.
ffmpeg -hide_banner -loglevel error -y \
    -i "$SOURCE_CAPTURE" \
    -filter_complex \
    "color=c=white:s=368x260:r=1[background];[background][0:v]overlay=shortest=1:format=auto,format=rgb24" \
    -frames:v 1 \
    -map_metadata -1 \
    "$TEMP_DIR/capture.png"
swift "$ROOT_DIR/scripts/strip-png-metadata.swift" \
    "$TEMP_DIR/capture.png" \
    "$CAPTURE_OUTPUT"

# The exact committed Edit source is already opaque. Re-encode it as RGB24 and
# remove every ancillary PNG chunk so the public derivative carries no host ICC.
ffmpeg -hide_banner -loglevel error -y \
    -i "$SOURCE_EDIT" \
    -vf format=rgb24 \
    -frames:v 1 \
    -map_metadata -1 \
    "$TEMP_DIR/edit.png"
swift "$ROOT_DIR/scripts/strip-png-metadata.swift" \
    "$TEMP_DIR/edit.png" \
    "$EDIT_OUTPUT"

# Flatten the synthetic SwiftUI fixture over white and force opaque 8-bit RGB.
# The fixture generator performs no Apply action. The final metadata stripper
# retains only critical PNG chunks.
ffmpeg -hide_banner -loglevel error -y \
    -i "$SOURCE_REVIEW" \
    -filter_complex \
    "color=c=white:s=620x500:r=1[background];[background][0:v]overlay=shortest=1:format=auto,format=rgb24" \
    -frames:v 1 \
    -map_metadata -1 \
    "$TEMP_DIR/review.png"
swift "$ROOT_DIR/scripts/strip-png-metadata.swift" \
    "$TEMP_DIR/review.png" \
    "$REVIEW_OUTPUT"

# Hold each static screen long enough to read, with two restrained fades. The
# output is deliberately silent and ends at Review; it never simulates Apply.
ffmpeg -hide_banner -loglevel error -y \
    -loop 1 -framerate 30 -t 11.4 -i "$PUBLIC_DIR/screenshots/capture.png" \
    -loop 1 -framerate 30 -t 12.4 -i "$PUBLIC_DIR/screenshots/edit.png" \
    -loop 1 -framerate 30 -t 14.4 -i "$REVIEW_OUTPUT" \
    -filter_complex \
    "[0:v]scale=736:520:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0xf4f8fc,setsar=1[capture];\
[1:v]scale=900:568:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0xf4f8fc,setsar=1[edit];\
[2:v]scale=744:600:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0xf4f8fc,setsar=1[review];\
[capture][edit]xfade=transition=fade:duration=0.6:offset=10.8[capture-edit];\
[capture-edit][review]xfade=transition=fade:duration=0.6:offset=22.6,format=yuv420p[video]" \
    -map "[video]" \
    -an \
    -t 37 \
    -r 30 \
    -c:v libx264 \
    -crf 20 \
    -preset slow \
    -pix_fmt yuv420p \
    -movflags +faststart \
    -map_metadata -1 \
    "$VIDEO_OUTPUT"

echo "Built public Capture, Edit, Review screenshots and silent demo."
