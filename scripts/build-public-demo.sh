#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REVIEW="${1:-$ROOT_DIR/docs/evidence/public-release-assets/workflow/23-apply-preview-en-initial.png}"
PUBLIC_DIR="$ROOT_DIR/site/public"
REVIEW_OUTPUT="$PUBLIC_DIR/screenshots/review.png"
VIDEO_OUTPUT="$PUBLIC_DIR/demo/desk-setup-switcher.mp4"

fail() {
    echo "Public demo build failed: $*" >&2
    exit 1
}

for command_name in ffmpeg; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required command is unavailable: $command_name"
done

[[ -f "$SOURCE_REVIEW" ]] || fail "missing synthetic review fixture: $SOURCE_REVIEW"
[[ -f "$PUBLIC_DIR/screenshots/capture.png" ]] || fail "missing public Capture screenshot"
[[ -f "$PUBLIC_DIR/screenshots/edit.png" ]] || fail "missing public Edit screenshot"

# Flatten the synthetic SwiftUI fixture over white and force opaque 8-bit RGB.
# `-map_metadata -1` removes source metadata; the fixture generator performs no
# Apply action.
ffmpeg -hide_banner -loglevel error -y \
    -i "$SOURCE_REVIEW" \
    -filter_complex \
    "color=c=white:s=620x500:r=1[background];[background][0:v]overlay=shortest=1:format=auto,format=rgb24" \
    -frames:v 1 \
    -map_metadata -1 \
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

echo "Built public review screenshot and silent demo."
