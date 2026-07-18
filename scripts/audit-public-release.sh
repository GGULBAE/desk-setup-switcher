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
secret_pattern='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|github_pat_[0-9A-Za-z_]{20,}|gh[pousr]_[0-9A-Za-z]{20,}|(^|[^A-Za-z0-9])sk-(proj-)?[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)'
home_path_pattern='/Users/[^/[:space:]]+/(Desktop|Documents|Downloads|Library)'

# Include tracked working-tree content so the command is useful before the
# release-preparation commit as well as after it. Only path metadata is kept.
git grep -I -l -E "$secret_pattern" -- . 2>/dev/null \
    | sed 's/^/WORKTREE:/' \
    >>"$secret_hits" || true

git grep -I -n -E "$home_path_pattern" -- . 2>/dev/null \
    | grep -v '/Users/example/' \
    | cut -d: -f1 \
    | sed 's/^/WORKTREE:/' \
    >>"$home_path_hits" || true

while IFS= read -r commit; do
    git grep -I -l -E "$secret_pattern" "$commit" >>"$secret_hits" 2>/dev/null || true

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
        | grep -Eq "$secret_pattern|/Users/|/home/[^/[:space:]]+/"; then
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
