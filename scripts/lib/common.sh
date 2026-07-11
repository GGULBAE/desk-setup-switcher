#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
ARTIFACTS_DIR="$ROOT_DIR/artifacts"
INFO_PLIST="$ROOT_DIR/Config/Info.plist"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if xcodebuild -version >/dev/null 2>&1; then
        DEVELOPER_DIR="$(xcode-select -p)"
    elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo "Full Xcode is required. Install Xcode or set DEVELOPER_DIR." >&2
        exit 1
    fi
fi

export DEVELOPER_DIR

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || ! xcodebuild -version >/dev/null 2>&1; then
    echo "DEVELOPER_DIR must point to a full Xcode installation: $DEVELOPER_DIR" >&2
    exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Missing application Info.plist: $INFO_PLIST" >&2
    exit 1
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_value CFBundleVersion)"
APP_NAME="$(plist_value CFBundleDisplayName)"
EXECUTABLE_NAME="$(plist_value CFBundleExecutable)"
BUNDLE_IDENTIFIER="$(plist_value CFBundleIdentifier)"
MINIMUM_SYSTEM_VERSION="$(plist_value LSMinimumSystemVersion)"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "CFBundleShortVersionString must contain one to three numeric components: $VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "CFBundleVersion must contain one to three numeric components: $BUILD_NUMBER" >&2
    exit 1
fi

if [[ -z "$APP_NAME" || "$APP_NAME" == */* || "$APP_NAME" == *$'\n'* || "$APP_NAME" == *$'\r'* || \
    -z "$EXECUTABLE_NAME" || "$EXECUTABLE_NAME" == */* || "$EXECUTABLE_NAME" == *$'\n'* || "$EXECUTABLE_NAME" == *$'\r'* ]]; then
    echo "Bundle display and executable names must be non-empty path components." >&2
    exit 1
fi

if [[ ! "$BUNDLE_IDENTIFIER" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$ ]]; then
    echo "Invalid CFBundleIdentifier: $BUNDLE_IDENTIFIER" >&2
    exit 1
fi

if [[ ! "$MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Invalid LSMinimumSystemVersion: $MINIMUM_SYSTEM_VERSION" >&2
    exit 1
fi

export ROOT_DIR BUILD_DIR ARTIFACTS_DIR INFO_PLIST VERSION BUILD_NUMBER APP_NAME
export EXECUTABLE_NAME BUNDLE_IDENTIFIER MINIMUM_SYSTEM_VERSION
