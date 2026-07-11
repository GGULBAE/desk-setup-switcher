#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"
swift test --parallel -Xswiftc -warnings-as-errors
