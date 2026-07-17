#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"

# NSPopover owns process-global AppKit presentation state. Running its native
# shell regression alongside the offscreen NSWindow render suites can crash the
# Swift Testing helper after the assertions pass, so keep the pure/mock suite
# parallel and execute the one native presentation contract in isolation.
NATIVE_POPOVER_TEST='DeskSetupSwitcherTests.TrayPopoverControllerTests/nativePopoverPreservesAttachedWrapperFrame\(\)'

swift test \
  --parallel \
  --skip "$NATIVE_POPOVER_TEST" \
  -Xswiftc -warnings-as-errors

swift test \
  --filter "$NATIVE_POPOVER_TEST" \
  -Xswiftc -warnings-as-errors
