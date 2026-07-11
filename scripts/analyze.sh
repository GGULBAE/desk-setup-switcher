#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"
ruby scripts/generate-xcode-project.rb --check
xcodebuild \
    -project DeskSetupSwitcher.xcodeproj \
    -scheme DeskSetupSwitcher \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/xcode-analyze" \
    analyze \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
