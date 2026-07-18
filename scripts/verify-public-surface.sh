#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

site_directory="$ROOT_DIR/site"

[[ -f "$site_directory/package-lock.json" ]] || {
    echo "Public-surface verification requires site/package-lock.json." >&2
    exit 1
}
[[ -x "$site_directory/node_modules/.bin/eslint" ]] || {
    echo "Public-surface dependencies are missing. Run 'npm ci --ignore-scripts' in site/." >&2
    exit 1
}

"$ROOT_DIR/scripts/verify-public-assets.sh"
(
    cd "$site_directory"
    npm run verify
)

echo "Public site and release assets verified."
