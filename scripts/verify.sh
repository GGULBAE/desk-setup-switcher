#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

"$ROOT_DIR/scripts/lint.sh"
"$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/build.sh"
"$ROOT_DIR/scripts/analyze.sh"
"$ROOT_DIR/scripts/package.sh"
"$ROOT_DIR/scripts/verify-package.sh"
