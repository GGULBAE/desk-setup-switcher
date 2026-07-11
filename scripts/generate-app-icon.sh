#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

source_svg="$ROOT_DIR/Assets/AppIcon.svg"
output_icns="$ROOT_DIR/Assets/AppIcon.icns"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-icon.XXXXXX")"
iconset="$temporary_directory/AppIcon.iconset"
master_png="$temporary_directory/AppIcon-1024.png"
temporary_icns="$temporary_directory/AppIcon.icns"

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

[[ -f "$source_svg" ]] || {
    echo "Missing icon source: $source_svg" >&2
    exit 1
}

mkdir -p "$iconset"
sips -s format png "$source_svg" --out "$master_png" >/dev/null

render() {
    local pixels="$1"
    local output="$2"
    sips -z "$pixels" "$pixels" "$master_png" --out "$iconset/$output" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
cp "$master_png" "$iconset/icon_512x512@2x.png"

iconutil --convert icns --output "$temporary_icns" "$iconset"
chmod 0644 "$temporary_icns"
mv -f "$temporary_icns" "$output_icns"
printf 'Created %s\n' "$output_icns"
