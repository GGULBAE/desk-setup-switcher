#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"
assertions=0
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-app-bundle-tests.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

mock_bin="$temporary_root/mock-bin"
app_bundle="$temporary_root/$APP_NAME.app"
app_binary="$app_bundle/Contents/MacOS/$EXECUTABLE_NAME"
resources_directory="$app_bundle/Contents/Resources"
mkdir -p "$mock_bin" "$app_bundle/Contents/MacOS" "$resources_directory"
cp Config/Info.plist "$app_bundle/Contents/Info.plist"
cp Assets/AppIcon.icns "$resources_directory/AppIcon.icns"
for localization in en ko; do
    mkdir -p "$resources_directory/$localization.lproj"
    cp "Sources/DeskSetupSwitcher/Resources/$localization.lproj/InfoPlist.strings" \
        "$resources_directory/$localization.lproj/InfoPlist.strings"
    cp "Sources/DeskSetupSwitcher/Resources/$localization.lproj/Localizable.strings" \
        "$resources_directory/$localization.lproj/Localizable.strings"
done
printf '#!/usr/bin/env bash\nexit 0\n' >"$app_binary"
chmod 0755 "$app_binary"

cat >"$mock_bin/lipo" <<'MOCK_LIPO'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 2 && "$1" == -archs && -n "$2" ]] || exit 91
printf '%s\n' "${MOCK_LIPO_ARCHS:?}"
MOCK_LIPO

cat >"$mock_bin/vtool" <<'MOCK_VTOOL'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 4 && "$1" == -arch && "$3" == -show-build && -n "$4" ]] || exit 92
case "$2" in
    arm64) minos="${MOCK_ARM64_MINOS:?}" ;;
    x86_64) minos="${MOCK_X86_64_MINOS:?}" ;;
    *) exit 93 ;;
esac
printf '%s (architecture %s):\n' "$4" "$2"
printf '%s\n' \
    'Load command 11' \
    "      cmd ${MOCK_BUILD_VERSION_COMMAND:-LC_BUILD_VERSION}" \
    '  cmdsize 32' \
    " platform ${MOCK_BUILD_VERSION_PLATFORM:-MACOS}" \
    "    minos $minos" \
    '      sdk 26.5' \
    '   ntools 1' \
    '     tool LD' \
    '  version 1267.0'
if [[ "${MOCK_DUPLICATE_BUILD_VERSION:-}" == 1 ]]; then
    printf '%s\n' \
        'Load command 12' \
        '      cmd LC_BUILD_VERSION' \
        '  cmdsize 32' \
        ' platform MACOS' \
        "    minos $minos" \
        '      sdk 26.5' \
        '   ntools 0'
fi
MOCK_VTOOL
chmod 0755 "$mock_bin/lipo" "$mock_bin/vtool"

assert_succeeds_with_exact_output() {
    local expected="$1"
    shift
    local stdout="$temporary_root/success.stdout"
    local stderr="$temporary_root/success.stderr"
    if ! "$@" >"$stdout" 2>"$stderr"; then
        printf 'Expected app-bundle verification to succeed:\n' >&2
        cat "$stderr" >&2
        exit 1
    fi
    [[ "$(tr -d '\n' <"$stdout")" == "$expected" && ! -s "$stderr" ]] || {
        printf 'App-bundle verification success evidence was not deterministic.\n' >&2
        exit 1
    }
    assertions=$((assertions + 1))
}

assert_fails_with() {
    local expected_error="$1"
    shift
    local stdout="$temporary_root/failure.stdout"
    local stderr="$temporary_root/failure.stderr"
    if "$@" >"$stdout" 2>"$stderr"; then
        printf 'An invalid Mach-O compatibility fixture was accepted.\n' >&2
        exit 1
    fi
    grep -F -q -- "$expected_error" "$stderr" || {
        printf 'Expected app-bundle verification error is missing: %s\n' "$expected_error" >&2
        exit 1
    }
    assertions=$((assertions + 1))
}

verification_environment=(
    env
    "PATH=$mock_bin:$PATH"
    MOCK_ARM64_MINOS=14.0
    MOCK_X86_64_MINOS=14.0
)
app_binary_sha256="$(release_sha256 "$app_binary")"

assert_succeeds_with_exact_output \
    "Verified release app metadata and resources: architectures=arm64,x86_64; minos=arm64:14.0,x86_64:14.0; executable-sha256=$app_binary_sha256" \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='x86_64 arm64' \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release executable architectures are not exactly arm64 and x86_64.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64' \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release executable architectures are not exactly arm64 and x86_64.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='x86_64 arm64 i386' \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release arm64 LC_BUILD_VERSION minos is 15.0; expected 14.0.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64 x86_64' \
    MOCK_ARM64_MINOS=15.0 \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release x86_64 LC_BUILD_VERSION minos is 13.6; expected 14.0.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64 x86_64' \
    MOCK_X86_64_MINOS=13.6 \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release arm64 slice must contain exactly one macOS LC_BUILD_VERSION command.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64 x86_64' \
    MOCK_BUILD_VERSION_COMMAND=LC_VERSION_MIN_MACOSX \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release arm64 slice must contain exactly one macOS LC_BUILD_VERSION command.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64 x86_64' \
    MOCK_BUILD_VERSION_PLATFORM=IOS \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

assert_fails_with 'Release arm64 slice must contain exactly one macOS LC_BUILD_VERSION command.' \
    "${verification_environment[@]}" MOCK_LIPO_ARCHS='arm64 x86_64' \
    MOCK_DUPLICATE_BUILD_VERSION=1 \
    "$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$app_bundle"

printf 'Release app-bundle compatibility mock tests passed (%d assertions).\n' "$assertions"
