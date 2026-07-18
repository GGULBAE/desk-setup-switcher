#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "Public-release history audit requires a complete Git checkout." >&2
    echo "Fetch full history before retrying (for Actions checkout, use fetch-depth: 0)." >&2
    exit 1
fi

secret_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-secret-hits.XXXXXX")"
home_path_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-home-hits.XXXXXX")"
image_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-image-hits.XXXXXX")"

cleanup() {
    rm -f "$secret_hits" "$home_path_hits" "$image_hits"
}
trap cleanup EXIT

# Keep this list deliberately narrow and high-confidence. The audit reports only
# commit/path metadata so a suspected credential is never echoed back to logs.
secret_pattern='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|github_pat_[0-9A-Za-z_]{20,}|gh[pousr]_[0-9A-Za-z]{20,}|(^|[^A-Za-z0-9])sk-(proj-)?[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,})'
private_key_header_pattern='-----BEGIN '
home_path_pattern='/Users/[^/[:space:]]+/(Desktop|Documents|Downloads|Library)'

# A PEM marker can legitimately appear in validation code. Require a plausible
# base64 body and matching footer, in either plain or escaped form, so embedded
# JSON/environment values still fail without allowlisting release-tooling paths.
contains_private_key_material() {
    local scanner_status=0
    ruby -e '
      content = STDIN.read.b
      label = "((?:(?:RSA|EC|OPENSSH|DSA|ENCRYPTED) )?PRIVATE KEY)"
      legacy_plain = "(?:Proc-Type:[ \\t]*4,ENCRYPTED\\r?\\nDEK-Info:[ \\t]*[A-Z0-9-]+,[0-9A-Fa-f]+\\r?\\n(?:\\r?\\n)?)?"
      legacy_escaped = "(?:Proc-Type:[ \\t]*4,ENCRYPTED(?:\\\\r)?\\\\nDEK-Info:[ \\t]*[A-Z0-9-]+,[0-9A-Fa-f]+(?:\\\\r)?\\\\n(?:(?:\\\\r)?\\\\n)?)?"
      body_plain = "[A-Za-z0-9+/]{16,}={0,2}\\r?\\n(?:[A-Za-z0-9+/]{4,}={0,2}\\r?\\n)*"
      body_escaped = "[A-Za-z0-9+/]{16,}={0,2}(?:\\\\r)?\\\\n(?:[A-Za-z0-9+/]{4,}={0,2}(?:\\\\r)?\\\\n)*"
      plain = Regexp.new(
        "-----BEGIN #{label}-----\\r?\\n#{legacy_plain}#{body_plain}-----END \\1-----",
        Regexp::NOENCODING
      )
      escaped = Regexp.new(
        "-----BEGIN #{label}-----(?:\\\\r)?\\\\n#{legacy_escaped}#{body_escaped}-----END \\1-----",
        Regexp::NOENCODING
      )
      escaped_content = content.gsub(%q(\/).b, "/".b)
      exit(plain.match?(content) || escaped.match?(escaped_content) ? 0 : 3)
    ' || scanner_status=$?
    case "$scanner_status" in
        0) return 0 ;;
        3) return 1 ;;
        *)
            echo "Public-release credential material scanner failed closed." >&2
            return 0
            ;;
    esac
}

# Fail closed if future edits weaken either the detector or its false-positive
# boundary. These probes are generated in memory and never printed or persisted.
private_key_marker='PRIVATE KEY'
private_key_body='QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo='
private_key_escaped_solidus_body='QUJDREVGR0hJSktMTU5P\/Q=='
encrypted_private_key_marker='RSA PRIVATE KEY'
private_key_dek='AES-256-CBC,00112233445566778899AABBCCDDEEFF'
{
    printf '%s\n' "-----BEGIN $private_key_marker-----"
    printf '%s\n' "$private_key_body"
    printf '%s\n' "-----END $private_key_marker-----"
} | contains_private_key_material || {
    echo "Public-release credential audit failed its plain PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $private_key_marker-----\\n${private_key_body}\\n-----END $private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $private_key_marker-----\\n${private_key_escaped_solidus_body}\\n-----END $private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped-solidus PEM self-check." >&2
    exit 1
}
{
    printf '%s\n' "-----BEGIN $encrypted_private_key_marker-----"
    printf '%s\n' 'Proc-Type: 4,ENCRYPTED'
    printf 'DEK-Info: %s\n\n' "$private_key_dek"
    printf '%s\n' "$private_key_body"
    printf '%s\n' "-----END $encrypted_private_key_marker-----"
} | contains_private_key_material || {
    echo "Public-release credential audit failed its encrypted PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $encrypted_private_key_marker-----\\nProc-Type: 4,ENCRYPTED\\nDEK-Info: ${private_key_dek}\\n\\n${private_key_body}\\n-----END $encrypted_private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped encrypted PEM self-check." >&2
    exit 1
}
if printf '%s\n' "grep -q '^-----BEGIN $private_key_marker-----$'" \
    | contains_private_key_material; then
    echo "Public-release credential audit matched a marker-only validator." >&2
    exit 1
fi

# Include tracked working-tree content so the command is useful before the
# release-preparation commit as well as after it. Only path metadata is kept.
git grep -I -l -E "$secret_pattern" -- . 2>/dev/null \
    | sed 's/^/WORKTREE:/' \
    >>"$secret_hits" || true

while IFS= read -r path; do
    if [[ ! -f "$path" || -L "$path" ]] || contains_private_key_material <"$path"; then
        printf 'WORKTREE:%s\n' "$path" >>"$secret_hits"
    fi
done < <(git grep -I -l -F -e "$private_key_header_pattern" -- . 2>/dev/null || true)

git grep -I -n -E "$home_path_pattern" -- . 2>/dev/null \
    | grep -v '/Users/example/' \
    | cut -d: -f1 \
    | sed 's/^/WORKTREE:/' \
    >>"$home_path_hits" || true

while IFS= read -r commit; do
    git grep -I -l -E "$secret_pattern" "$commit" >>"$secret_hits" 2>/dev/null || true

    while IFS= read -r candidate; do
        path="${candidate#*:}"
        if git show "${commit}:${path}" | contains_private_key_material; then
            printf '%s:%s\n' "$commit" "$path" >>"$secret_hits"
        fi
    done < <(
        git grep -I -l -F -e "$private_key_header_pattern" "$commit" -- 2>/dev/null || true
    )

    # /Users/example is intentional synthetic redaction-test data. Any other
    # concrete macOS home path is unsuitable for public history.
    git grep -I -n -E "$home_path_pattern" "$commit" 2>/dev/null \
        | grep -v '/Users/example/' \
        | awk -F: '{ print $1 ":" $2 ":" $3 }' \
        >>"$home_path_hits" || true
done < <(git rev-list --all)

# Inspect every historical image blob, not just the current checkout. strings is
# intentionally used as a conservative metadata/path detector; image pixels are
# reviewed separately through the checked-in synthetic evidence process.
while IFS=$'\t' read -r object path; do
    if git cat-file blob "$object" \
        | strings \
        | grep -E "$secret_pattern|/Users/|/home/[^/[:space:]]+/" >/dev/null \
        || git cat-file blob "$object" | strings | contains_private_key_material; then
        printf '%s:%s\n' "$object" "$path" >>"$image_hits"
    fi
done < <(
    git rev-list --objects --all \
        | awk 'BEGIN { OFS = "\t" } tolower($2) ~ /\.(png|jpe?g|icns)$/ { print $1, $2 }'
)

placeholder_pattern='TBD''_FINAL_[A-Z0-9_]+|COMMIT''_PENDING|CHANGE''ME'
if git grep -I -n -E "$placeholder_pattern" -- \
    ':!Tests/**' ':!docs/evidence/**'; then
    echo "Unresolved public-release placeholder found in the current tree." >&2
    exit 1
fi

if [[ -s "$secret_hits" ]]; then
    echo "Potential credential pattern found in Git history (values suppressed):" >&2
    sort -u "$secret_hits" >&2
    exit 1
fi

if [[ -s "$home_path_hits" ]]; then
    echo "Concrete personal home path found in Git history (values suppressed):" >&2
    sort -u "$home_path_hits" >&2
    exit 1
fi

if [[ -s "$image_hits" ]]; then
    echo "Potential secret or personal path found in historical image metadata:" >&2
    sort -u "$image_hits" >&2
    exit 1
fi

echo "Public-release history and asset metadata audit passed."
