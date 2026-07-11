#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

rm -rf "$BUILD_DIR" "$ARTIFACTS_DIR"
