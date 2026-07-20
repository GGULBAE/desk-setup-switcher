#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_DIR="$ROOT_DIR/site/public"
CHECKSUM_FILE="$PUBLIC_DIR/assets.sha256"
SOURCE_CHECKSUM_FILE="$ROOT_DIR/docs/evidence/public-release-assets/sources.sha256"

fail() {
    echo "Public asset verification failed: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

for command_name in awk cmp ffmpeg ffprobe grep ruby sed shasum sips stat strings; do
    require_command "$command_name"
done

expected_assets=(
    "app-icon.svg"
    "demo/captions.en.vtt"
    "demo/captions.ko.vtt"
    "demo/desk-setup-switcher.mp4"
    "og.png"
    "screenshots/capture.png"
    "screenshots/edit.png"
    "screenshots/review.png"
)

expected_sources=(
    "docs/evidence/public-release-assets/f27c3f2/capture/01-empty-en-light.ax.txt"
    "docs/evidence/public-release-assets/f27c3f2/capture/01-empty-en-light.png"
    "docs/evidence/public-release-assets/f27c3f2/edit/13-display-en-light.ax.txt"
    "docs/evidence/public-release-assets/f27c3f2/edit/13-display-en-light.png"
    "docs/evidence/public-release-assets/f27c3f2/review/23-apply-preview-en-initial.ax.txt"
    "docs/evidence/public-release-assets/f27c3f2/review/23-apply-preview-en-initial.png"
    "docs/evidence/public-release-assets/f27c3f2/review/24-apply-preview-ko-refreshed.ax.txt"
    "docs/evidence/public-release-assets/f27c3f2/review/24-apply-preview-ko-refreshed.png"
    "docs/evidence/public-release-assets/f27c3f2/review/25-apply-preview-ko-minimum-large-text.ax.txt"
    "docs/evidence/public-release-assets/f27c3f2/review/25-apply-preview-ko-minimum-large-text.png"
    "docs/evidence/public-release-assets/og-background-imagegen.png"
)

for relative_path in "${expected_assets[@]}"; do
    [[ -f "$PUBLIC_DIR/$relative_path" ]] || fail "missing required asset: site/public/$relative_path"
done

cmp -s "$ROOT_DIR/Assets/AppIcon.svg" "$PUBLIC_DIR/app-icon.svg" ||
    fail "site/public/app-icon.svg is not an exact copy of Assets/AppIcon.svg"

image_property() {
    local image_path="$1"
    local property="$2"
    sips -g "$property" "$image_path" 2>/dev/null |
        awk -F': ' -v property="$property" '$1 ~ property { print $2; exit }'
}

verify_png_properties() {
    local image_path="$1"
    local label="$2"
    local expected_width="$3"
    local expected_height="$4"
    local expected_alpha="$5"
    local actual_width actual_height actual_format actual_alpha actual_profile

    actual_width="$(image_property "$image_path" pixelWidth)"
    actual_height="$(image_property "$image_path" pixelHeight)"
    actual_format="$(image_property "$image_path" format)"
    actual_alpha="$(image_property "$image_path" hasAlpha)"
    actual_profile="$(image_property "$image_path" profile)"

    [[ "$actual_width" == "$expected_width" && "$actual_height" == "$expected_height" ]] ||
        fail "$label is ${actual_width:-unknown}x${actual_height:-unknown}; expected ${expected_width}x${expected_height}"
    [[ "$actual_format" == "png" ]] || fail "$label is not encoded as PNG"
    [[ "$actual_alpha" == "$expected_alpha" ]] ||
        fail "$label hasAlpha is ${actual_alpha:-unknown}; expected $expected_alpha"
    [[ "$actual_profile" == "<nil>" ]] ||
        fail "$label must not embed an ICC profile (found: ${actual_profile:-unknown})"
}

verify_png_properties "$PUBLIC_DIR/screenshots/capture.png" "screenshots/capture.png" 368 260 no
verify_png_properties "$PUBLIC_DIR/screenshots/edit.png" "screenshots/edit.png" 900 568 no
verify_png_properties "$PUBLIC_DIR/screenshots/review.png" "screenshots/review.png" 620 500 no
verify_png_properties "$PUBLIC_DIR/og.png" "og.png" 1280 640 no

SOURCE_FIXTURE_ROOT="$ROOT_DIR/docs/evidence/public-release-assets/f27c3f2"
verify_png_properties \
    "$SOURCE_FIXTURE_ROOT/capture/01-empty-en-light.png" \
    "f27c3f2/capture/01-empty-en-light.png" 368 260 yes
verify_png_properties \
    "$SOURCE_FIXTURE_ROOT/edit/13-display-en-light.png" \
    "f27c3f2/edit/13-display-en-light.png" 900 568 no
verify_png_properties \
    "$SOURCE_FIXTURE_ROOT/review/23-apply-preview-en-initial.png" \
    "f27c3f2/review/23-apply-preview-en-initial.png" 620 500 yes
verify_png_properties \
    "$SOURCE_FIXTURE_ROOT/review/24-apply-preview-ko-refreshed.png" \
    "f27c3f2/review/24-apply-preview-ko-refreshed.png" 620 500 yes
verify_png_properties \
    "$SOURCE_FIXTURE_ROOT/review/25-apply-preview-ko-minimum-large-text.png" \
    "f27c3f2/review/25-apply-preview-ko-minimum-large-text.png" 520 360 yes

metadata_stripped_pngs=(
    "$PUBLIC_DIR/screenshots/capture.png"
    "$PUBLIC_DIR/screenshots/edit.png"
    "$PUBLIC_DIR/screenshots/review.png"
    "$PUBLIC_DIR/og.png"
    "$SOURCE_FIXTURE_ROOT/capture/01-empty-en-light.png"
    "$SOURCE_FIXTURE_ROOT/edit/13-display-en-light.png"
    "$SOURCE_FIXTURE_ROOT/review/23-apply-preview-en-initial.png"
    "$SOURCE_FIXTURE_ROOT/review/24-apply-preview-ko-refreshed.png"
    "$SOURCE_FIXTURE_ROOT/review/25-apply-preview-ko-minimum-large-text.png"
)
if ! ruby - "${metadata_stripped_pngs[@]}" <<'RUBY'
signature = "\x89PNG\r\n\x1a\n".b
allowed_chunks = %w[IHDR PLTE IDAT IEND]

ARGV.each do |path|
  data = File.binread(path)
  raise "#{path}: invalid PNG signature" unless data.start_with?(signature)

  offset = signature.bytesize
  chunks = []
  loop do
    raise "#{path}: truncated PNG chunk" if offset + 12 > data.bytesize

    length = data.byteslice(offset, 4).unpack1("N")
    chunk_end = offset + 12 + length
    raise "#{path}: truncated PNG chunk payload" if chunk_end > data.bytesize

    chunk_type = data.byteslice(offset + 4, 4)
    raise "#{path}: unexpected PNG chunk #{chunk_type.inspect}" unless allowed_chunks.include?(chunk_type)

    chunks << chunk_type
    offset = chunk_end
    break if chunk_type == "IEND"
  end

  raise "#{path}: IHDR must be first" unless chunks.first == "IHDR"
  raise "#{path}: PNG must contain image data" unless chunks.include?("IDAT")
  raise "#{path}: trailing bytes after IEND" unless offset == data.bytesize
end
RUBY
then
    fail "normalized source and public PNGs must contain only critical chunks and no trailing data"
fi

og_size="$(stat -f '%z' "$PUBLIC_DIR/og.png")"
[[ "$og_size" -le 1048576 ]] || fail "og.png must remain at or below 1 MiB"

# Keep this deliberately high-confidence. Pixel content is reviewed against the
# synthetic fixtures in docs/RELEASE-ASSET-PROVENANCE.md; this scan covers
# embedded paths, credential-shaped data, private network values, and known
# device-specific ICC descriptions that must not survive normalization.
sensitive_pattern='(/Users/[^/[:space:]]+|/home/[^/[:space:]]+|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|github_pat_[0-9A-Za-z_]{20,}|gh[pousr]_[0-9A-Za-z]{20,}|(^|[^A-Za-z0-9])sk-(proj-)?[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password[[:space:]]*[:=]|api[_-]?key[[:space:]]*[:=]|bearer[[:space:]]+[A-Za-z0-9._-]+|ssid[[:space:]]*[:=]|latitude[[:space:]]*[:=]|longitude[[:space:]]*[:=]|device[ _-]?(uid|uuid)[[:space:]]*[:=]|serial[ _-]?(number|no)[[:space:]]*[:=]|([0-9]{1,3}\.){3}[0-9]{1,3}|MSI[[:space:]]+MAG|Color LCD|DELL[[:space:]]+U[0-9]|LG[[:space:]]+UltraFine|BenQ[[:space:]]+[A-Z0-9]|ASUS[[:space:]]+[A-Z0-9])'

for relative_path in "${expected_assets[@]}"; do
    if LC_ALL=C strings -a "$PUBLIC_DIR/$relative_path" | grep -Eiq "$sensitive_pattern"; then
        fail "potential private data or device-specific metadata found in site/public/$relative_path"
    fi
done

for relative_path in "${expected_sources[@]}"; do
    if LC_ALL=C strings -a "$ROOT_DIR/$relative_path" | grep -Eiq "$sensitive_pattern"; then
        fail "potential private data or device-specific metadata found in $relative_path"
    fi
done

video_path="$PUBLIC_DIR/demo/desk-setup-switcher.mp4"
video_stream_count="$(
    ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$video_path" |
        awk 'NF { count += 1 } END { print count + 0 }'
)"
audio_stream_count="$(
    ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$video_path" |
        awk 'NF { count += 1 } END { print count + 0 }'
)"
video_codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$video_path")"
video_width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$video_path")"
video_height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$video_path")"
video_pixel_format="$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$video_path")"
video_duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video_path")"

[[ "$video_stream_count" == 1 ]] || fail "demo MP4 must contain exactly one video stream"
[[ "$audio_stream_count" == 0 ]] || fail "demo MP4 must not contain an audio stream"
[[ "$video_codec" == "h264" ]] || fail "demo MP4 codec is $video_codec; expected h264"
[[ "$video_width" == 1280 && "$video_height" == 720 ]] ||
    fail "demo MP4 is ${video_width}x${video_height}; expected 1280x720"
[[ "$video_pixel_format" == "yuv420p" ]] ||
    fail "demo MP4 pixel format is $video_pixel_format; expected yuv420p"
awk -v duration="$video_duration" 'BEGIN {
    difference = duration - 37.0
    if (difference < 0) difference = -difference
    exit difference <= 0.01 ? 0 : 1
}' || fail "demo MP4 duration is $video_duration seconds; expected 37 seconds"

timestamp_to_milliseconds() {
    local timestamp="$1"
    local minutes rest seconds milliseconds
    minutes="${timestamp%%:*}"
    rest="${timestamp#*:}"
    seconds="${rest%%.*}"
    milliseconds="${rest#*.}"
    printf '%d' "$((10#$minutes * 60000 + 10#$seconds * 1000 + 10#$milliseconds))"
}

verify_vtt() {
    local relative_path="$1"
    local vtt_path="$PUBLIC_DIR/$relative_path"
    local timing_count first_start last_end previous_end line start end start_ms end_ms

    [[ "$(sed -n '1p' "$vtt_path")" == "WEBVTT" ]] ||
        fail "$relative_path must begin with WEBVTT"
    if LC_ALL=C grep -q $'\r' "$vtt_path"; then
        fail "$relative_path must use LF line endings"
    fi

    timing_count="$(
        LC_ALL=C grep -Ec '^[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] --> [0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]$' "$vtt_path"
    )"
    [[ "$timing_count" == 5 ]] || fail "$relative_path must contain exactly five valid cues"

    awk '
        NR == 1 { if ($0 != "WEBVTT") exit 1; next }
        /^[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9] --> [0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]$/ {
            if (waiting_for_text) exit 2
            cue_count += 1
            waiting_for_text = 1
            next
        }
        waiting_for_text && NF > 0 {
            text_count += 1
            waiting_for_text = 0
        }
        END {
            if (cue_count != 5 || text_count != cue_count || waiting_for_text) exit 3
        }
    ' "$vtt_path" || fail "$relative_path has a cue without caption text"

    first_start=""
    last_end=""
    previous_end=-1
    while IFS= read -r line; do
        start="${line%% --> *}"
        end="${line##* --> }"
        start_ms="$(timestamp_to_milliseconds "$start")"
        end_ms="$(timestamp_to_milliseconds "$end")"
        [[ "$end_ms" -gt "$start_ms" ]] || fail "$relative_path contains an empty or reversed cue"
        [[ "$start_ms" -ge "$previous_end" ]] || fail "$relative_path contains overlapping cues"
        [[ -n "$first_start" ]] || first_start="$start"
        last_end="$end"
        previous_end="$end_ms"
    done < <(LC_ALL=C grep ' --> ' "$vtt_path")

    [[ "$first_start" == "00:00.000" ]] || fail "$relative_path must start at 00:00.000"
    [[ "$last_end" == "00:37.000" ]] || fail "$relative_path must end at 00:37.000"
}

verify_vtt "demo/captions.en.vtt"
verify_vtt "demo/captions.ko.vtt"

verify_checksum_manifest() {
    local manifest_path="$1"
    local base_directory="$2"
    local manifest_label="$3"
    shift 3
    local expected_paths=("$@")
    local checksum relative_path unexpected expected_path match_count
    local checksum_paths=()

    [[ -f "$manifest_path" ]] || fail "missing required checksum manifest: $manifest_label"
    while IFS=' ' read -r checksum relative_path unexpected; do
        relative_path="${relative_path#\*}"
        [[ "$checksum" =~ ^[0-9a-f]{64}$ && -n "$relative_path" && -z "${unexpected:-}" ]] ||
            fail "$manifest_label contains an invalid entry"
        [[ "$relative_path" != /* && "$relative_path" != *"../"* ]] ||
            fail "$manifest_label contains an unsafe path: $relative_path"
        checksum_paths[${#checksum_paths[@]}]="$relative_path"
    done <"$manifest_path"

    [[ "${#checksum_paths[@]}" == "${#expected_paths[@]}" ]] ||
        fail "$manifest_label must contain exactly ${#expected_paths[@]} entries"
    for expected_path in "${expected_paths[@]}"; do
        match_count=0
        for checksum_path in "${checksum_paths[@]}"; do
            [[ "$checksum_path" == "$expected_path" ]] && match_count=$((match_count + 1))
        done
        [[ "$match_count" == 1 ]] ||
            fail "$manifest_label must contain exactly one entry for $expected_path"
    done

    (cd "$base_directory" && shasum -a 256 -c "$manifest_path")
}

verify_checksum_manifest \
    "$CHECKSUM_FILE" \
    "$PUBLIC_DIR" \
    "site/public/assets.sha256" \
    "${expected_assets[@]}"

verify_checksum_manifest \
    "$SOURCE_CHECKSUM_FILE" \
    "$ROOT_DIR" \
    "docs/evidence/public-release-assets/sources.sha256" \
    "${expected_sources[@]}"

echo "Public release assets verified."
