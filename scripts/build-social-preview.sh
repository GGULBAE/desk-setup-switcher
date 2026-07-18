#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKGROUND="${ROOT_DIR}/docs/evidence/public-release-assets/og-background-imagegen.png"
ICON_SVG="${ROOT_DIR}/site/public/app-icon.svg"
SCREENSHOT="${ROOT_DIR}/site/public/screenshots/edit.png"
OUTPUT="${ROOT_DIR}/site/public/og.png"

for command_name in ffmpeg sips swift; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: ${command_name} is required" >&2
        exit 1
    fi
done

for input_path in "${BACKGROUND}" "${ICON_SVG}" "${SCREENSHOT}"; do
    if [[ ! -f "${input_path}" ]]; then
        echo "error: missing input ${input_path}" >&2
        exit 1
    fi
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

sips -s format png "${ICON_SVG}" --out "${TEMP_DIR}/app-icon.png" >/dev/null

swift "${ROOT_DIR}/scripts/build-social-preview.swift" \
    "${BACKGROUND}" \
    "${TEMP_DIR}/app-icon.png" \
    "${SCREENSHOT}" \
    "${TEMP_DIR}/social-preview-with-alpha.png"

ffmpeg -hide_banner -loglevel error -y \
    -i "${TEMP_DIR}/social-preview-with-alpha.png" \
    -vf format=rgb24 \
    -frames:v 1 \
    -map_metadata -1 \
    "${TEMP_DIR}/social-preview-rgb.png"

swift "${ROOT_DIR}/scripts/strip-png-metadata.swift" \
    "${TEMP_DIR}/social-preview-rgb.png" \
    "${OUTPUT}"

echo "Wrote ${OUTPUT}"
