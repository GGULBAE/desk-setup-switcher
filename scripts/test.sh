#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"

# NSPopover owns process-global AppKit presentation state. Running its native
# shell regression through the Swift Testing helper crashes on macOS 15, and
# sharing it with the offscreen NSWindow render suites is unsafe. Keep the
# pure/mock suite parallel and execute the native XCTest contract in isolation.
NATIVE_POPOVER_TEST='DeskSetupSwitcherTests.NativePopoverRegressionTests/testNativePopoverPreservesAttachedWrapperFrame'

swift test \
  --parallel \
  --skip "$NATIVE_POPOVER_TEST" \
  -Xswiftc -warnings-as-errors

swift test \
  --filter "$NATIVE_POPOVER_TEST" \
  -Xswiftc -warnings-as-errors
