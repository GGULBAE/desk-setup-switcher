#!/usr/bin/env bash

set -euo pipefail
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_SCRIPT="$ROOT_DIR/scripts/audit-public-release.sh"
REAL_GIT="$(command -v git)"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-public-audit-tests.XXXXXX")"
assertions=0

cleanup() {
    if [[ "${KEEP_PUBLIC_AUDIT_FIXTURES:-0}" == "1" ]]; then
        printf 'Preserved public-release audit fixtures at %s\n' "$temporary_root" >&2
        return
    fi
    rm -rf "$temporary_root"
}
trap cleanup EXIT

pass() {
    assertions=$((assertions + 1))
}

fail() {
    echo "Public-release audit fixture test failed: $*" >&2
    exit 1
}

new_repository() {
    local name="$1"
    local repository="$temporary_root/$name"
    mkdir -p "$repository/scripts"
    cp "$AUDIT_SCRIPT" "$repository/scripts/audit-public-release.sh"
    chmod 0755 "$repository/scripts/audit-public-release.sh"
    git -C "$repository" init -q -b master
    git -C "$repository" config user.name "Synthetic Audit Fixture"
    git -C "$repository" config user.email "audit-fixture@example.invalid"
    printf 'fixture baseline\n' >"$repository/README.md"
    git -C "$repository" add scripts/audit-public-release.sh README.md
    git -C "$repository" commit -q -m "fixture baseline"
    printf '%s\n' "$repository"
}

run_audit() {
    local repository="$1"
    local label="$2"
    last_stdout="$temporary_root/$label.stdout"
    last_stderr="$temporary_root/$label.stderr"
    set +e
    "$repository/scripts/audit-public-release.sh" >"$last_stdout" 2>"$last_stderr"
    last_status=$?
    set -e
}

run_audit_with_git_shim() {
    local repository="$1"
    local label="$2"
    local shim_directory="$3"
    last_stdout="$temporary_root/$label.stdout"
    last_stderr="$temporary_root/$label.stderr"
    set +e
    PATH="$shim_directory:$PATH" REAL_GIT="$REAL_GIT" \
        "$repository/scripts/audit-public-release.sh" >"$last_stdout" 2>"$last_stderr"
    last_status=$?
    set -e
}

assert_passes() {
    local repository="$1"
    local label="$2"
    run_audit "$repository" "$label"
    [[ "$last_status" == 0 ]] || fail "$label unexpectedly failed"
    grep -F -q 'Public-release history, privacy, and asset metadata audit passed.' "$last_stdout" ||
        fail "$label did not report the complete audit boundary"
    [[ ! -s "$last_stderr" ]] || fail "$label emitted unexpected stderr"
    pass
}

assert_fails_without_value() {
    local repository="$1"
    local label="$2"
    local category="$3"
    local value="$4"
    run_audit "$repository" "$label"
    [[ "$last_status" != 0 ]] || fail "$label unexpectedly passed"
    grep -F -q ":$category" "$last_stderr" || fail "$label did not report category $category"
    if grep -F -q -- "$value" "$last_stdout" "$last_stderr"; then
        fail "$label echoed the matched private value"
    fi
    pass
}

assert_legacy_fails_without_value() {
    local repository="$1"
    local label="$2"
    local heading="$3"
    local value="$4"
    run_audit "$repository" "$label"
    [[ "$last_status" != 0 ]] || fail "$label unexpectedly passed"
    grep -F -q "$heading" "$last_stderr" || fail "$label did not report the expected detector"
    grep -E -q ':(path-digest-[0-9a-f]{16})$' "$last_stderr" ||
        fail "$label did not suppress legacy path metadata"
    if grep -F -q -- "$value" "$last_stdout" "$last_stderr"; then
        fail "$label echoed the matched private value"
    fi
    pass
}

commit_then_delete() {
    local repository="$1"
    local relative_path="$2"
    git -C "$repository" add "$relative_path"
    git -C "$repository" commit -q -m "add audit probe"
    rm -f -- "$repository/$relative_path"
    git -C "$repository" add -u -- "$relative_path"
    git -C "$repository" commit -q -m "remove audit probe"
}

clean_repository="$(new_repository clean)"
cat >"$clean_repository/safe.txt" <<'SAFE'
SSID=<redacted>
location=synthetic-lab
deviceUID=example-device
address=192.0.2.44
alternate=198.51.100.19
service=203.0.113.71
ipv6=2001:db8::44
loopback=127.0.0.1
mapped_loopback=::ffff:7f00:1
SAFE
cat >"$clean_repository/SafeSettings.swift" <<'SAFE_SOURCE'
struct SafeSettings {
    let deviceUID: String
    let location: String?

    init(ssid: String, serialNumber: String) {
        let localizedCopy = "Choose a network, SSID: %@"
    }
}
SAFE_SOURCE
safe_binary_host="$(printf '10.%s' '250.251.252')"
printf '\000compressed-bytes-%s\000' "$safe_binary_host" >"$clean_repository/random.png"
git -C "$clean_repository" add safe.txt SafeSettings.swift random.png
git -C "$clean_repository" commit -q -m "add explicit safe fixtures"
assert_passes "$clean_repository" clean

# The repository audit test deliberately contains private-looking synthetic
# probes. Only its exact reviewed blob is exempt; changing the same path must
# immediately restore ordinary detection.
reviewed_self_repository="$(new_repository reviewed-audit-fixture)"
cp "$ROOT_DIR/scripts/test-audit-public-release.sh" \
    "$reviewed_self_repository/scripts/test-audit-public-release.sh"
git -C "$reviewed_self_repository" add scripts/test-audit-public-release.sh
git -C "$reviewed_self_repository" commit -q -m "add reviewed audit fixture"
assert_passes "$reviewed_self_repository" reviewed-audit-fixture
self_change_probe="$(printf '%s%s' 'UnexpectedDesk-' '3201')"
printf '\nSSID=%s\n' "$self_change_probe" \
    >>"$reviewed_self_repository/scripts/test-audit-public-release.sh"
assert_fails_without_value \
    "$reviewed_self_repository" reviewed-audit-fixture-change ssid "$self_change_probe"

probe_one="$(printf '%s%s' 'OfficeWest-' '4831')"
ssid_repository="$(new_repository labeled-network)"
printf 'SSID=%s\n' "$probe_one" >"$ssid_repository/private.txt"
commit_then_delete "$ssid_repository" private.txt
assert_fails_without_value "$ssid_repository" labeled-network ssid "$probe_one"

probe_two="$(printf '%s%s' '35.' '188777')"
coordinate_repository="$(new_repository labeled-coordinate)"
printf 'latitude=%s\n' "$probe_two" >"$coordinate_repository/private.json"
commit_then_delete "$coordinate_repository" private.json
assert_fails_without_value "$coordinate_repository" labeled-coordinate coordinates "$probe_two"

probe_three="$(printf '%s%s' 'RiverDistrict' 'Home')"
location_repository="$(new_repository labeled-location)"
printf 'location="%s"\n' "$probe_three" >"$location_repository/private.yml"
commit_then_delete "$location_repository" private.yml
assert_fails_without_value "$location_repository" labeled-location location "$probe_three"

probe_four="$(printf '%s%s' 'A1B2C3D4-E5F6-' '47A8-90B1-C2D3E4F50617')"
device_repository="$(new_repository labeled-device)"
printf 'deviceUID="%s"\n' "$probe_four" >"$device_repository/private.swift"
commit_then_delete "$device_repository" private.swift
assert_fails_without_value "$device_repository" labeled-device device-identifier "$probe_four"

probe_five="$(printf '%s%s' 'C02X9' '8ABCD12')"
serial_repository="$(new_repository labeled-serial)"
printf 'serialNumber=%s\n' "$probe_five" >"$serial_repository/private.plist"
commit_then_delete "$serial_repository" private.plist
assert_fails_without_value "$serial_repository" labeled-serial device-identifier "$probe_five"

probe_six="$(printf '10.%s' '23.45.67')"
ipv4_repository="$(new_repository private-ipv4)"
printf 'address=%s\n' "$probe_six" >"$ipv4_repository/private.md"
commit_then_delete "$ipv4_repository" private.md
assert_fails_without_value "$ipv4_repository" private-ipv4 ip-host "$probe_six"

probe_seven="$(printf '%s%s' 'fd42:9a71:' '4bc2::19')"
ipv6_repository="$(new_repository private-ipv6)"
printf 'address=%s\n' "$probe_seven" >"$ipv6_repository/private.md"
commit_then_delete "$ipv6_repository" private.md
assert_fails_without_value "$ipv6_repository" private-ipv6 ip-host "$probe_seven"

mapped_probe="$(printf '%s%s' '::ffff:0a17:' '2d43')"
mapped_repository="$(new_repository private-mapped-ipv4)"
printf 'address=%s\n' "$mapped_probe" >"$mapped_repository/private.md"
commit_then_delete "$mapped_repository" private.md
assert_fails_without_value "$mapped_repository" private-mapped-ipv4 ip-host "$mapped_probe"

probe_eight="$(printf '%s%s' 'N7M8P9Q0' 'R1S2')"
asset_repository="$(new_repository binary-asset)"
printf '\000metadata serialNumber=%s\000' "$probe_eight" >"$asset_repository/private.png"
git -C "$asset_repository" add private.png
git -C "$asset_repository" commit -q -m "add binary metadata probe"
assert_fails_without_value "$asset_repository" binary-asset device-identifier "$probe_eight"

probe_ten="$(printf '172.%s' '29.44.81')"
asset_host_repository="$(new_repository binary-asset-host)"
printf '\000metadata host=%s\000' "$probe_ten" >"$asset_host_repository/private.png"
commit_then_delete "$asset_host_repository" private.png
assert_fails_without_value "$asset_host_repository" binary-asset-host ip-host "$probe_ten"

probe_eleven="$(printf '%s%s' 'StudioFloor-' '2189')"
xml_repository="$(new_repository plist-network)"
printf '<plist><dict><key>SSID</key><string>%s</string></dict></plist>\n' "$probe_eleven" \
    >"$xml_repository/private.plist"
commit_then_delete "$xml_repository" private.plist
assert_fails_without_value "$xml_repository" plist-network ssid "$probe_eleven"

probe_twelve="$(printf '%s%s' 'PrivatePath-' '7391')"
path_repository="$(new_repository private-path)"
mkdir -p "$path_repository/exports"
private_relative_path="exports/archive:${probe_twelve}.txt"
printf 'SSID=%s\n' "$probe_twelve" >"$path_repository/$private_relative_path"
commit_then_delete "$path_repository" "$private_relative_path"
assert_fails_without_value "$path_repository" private-path ssid "$probe_twelve"
grep -E -q ':(path-digest-[0-9a-f]{16}):ssid$' "$last_stderr" ||
    fail "private-path did not suppress unsafe path metadata"

short_path_probe="$(printf '%s%s' 'Q' '7')"
short_path_repository="$(new_repository short-private-path)"
mkdir -p "$short_path_repository/exports"
short_relative_path="exports/${short_path_probe}.txt"
printf 'SSID=%s\n' "$short_path_probe" >"$short_path_repository/$short_relative_path"
commit_then_delete "$short_path_repository" "$short_relative_path"
assert_fails_without_value "$short_path_repository" short-private-path ssid "$short_path_probe"
grep -E -q ':(path-digest-[0-9a-f]{16}):ssid$' "$last_stderr" ||
    fail "short-private-path did not suppress short matched path metadata"

probe_thirteen="$(printf '%s%s' 'AccidentalDesk-' '6284')"
future_fixture_repository="$(new_repository future-test-fixture)"
mkdir -p "$future_fixture_repository/Tests"
printf 'func testAccidentalPrivateValue() {\n    let profile = Profile(ssid: "%s")\n}\n' "$probe_thirteen" \
    >"$future_fixture_repository/Tests/AccidentalFixture.swift"
commit_then_delete "$future_fixture_repository" Tests/AccidentalFixture.swift
assert_fails_without_value \
    "$future_fixture_repository" future-test-fixture ssid "$probe_thirteen"

probe_fourteen="$(printf '%s%s' 'ShellDesk-' '9137')"
shell_repository="$(new_repository shell-history)"
printf 'SSID="%s"\n' "$probe_fourteen" >"$shell_repository/private.sh"
commit_then_delete "$shell_repository" private.sh
assert_fails_without_value "$shell_repository" shell-history ssid "$probe_fourteen"

probe_fifteen="$(printf '%s%s' 'CommitDesk-' '4726')"
commit_message_repository="$(new_repository commit-message)"
printf 'SSID=%s\n' "$probe_fifteen" |
    git -C "$commit_message_repository" commit -q --allow-empty -F -
assert_fails_without_value \
    "$commit_message_repository" commit-message ssid "$probe_fifteen"

credential_message_probe="$(printf '%s%s' 'ghp_' 'Z9Y8X7W6V5U4T3S2R1Q0')"
credential_message_repository="$(new_repository credential-message)"
printf '%s\n' "$credential_message_probe" |
    git -C "$credential_message_repository" commit -q --allow-empty -F -
assert_legacy_fails_without_value \
    "$credential_message_repository" \
    credential-message \
    'Potential credential pattern found in Git history' \
    "$credential_message_probe"

probe_sixteen="$(printf '%s%s' 'TagDesk-' '5814')"
tag_message_repository="$(new_repository tag-message)"
printf 'SSID=%s\n' "$probe_sixteen" |
    git -C "$tag_message_repository" tag -a audit-probe -F -
assert_fails_without_value "$tag_message_repository" tag-message ssid "$probe_sixteen"

credential_probe="$(printf '%s%s' 'ghp_' 'A1B2C3D4E5F6G7H8I9J0')"
credential_repository="$(new_repository credential-path)"
mkdir -p "$credential_repository/exports"
credential_relative_path="exports/archive:${credential_probe}.txt"
printf '%s\n' "$credential_probe" >"$credential_repository/$credential_relative_path"
commit_then_delete "$credential_repository" "$credential_relative_path"
assert_legacy_fails_without_value \
    "$credential_repository" \
    credential-path \
    'Potential credential pattern found in Git history' \
    "$credential_probe"

home_user_probe="$(printf '%s%s' 'private-user-' '6402')"
home_path_probe="$(printf '/%s/%s/%s/archive.log' 'Users' "$home_user_probe" 'Projects')"
home_repository="$(new_repository home-path)"
mkdir -p "$home_repository/notes"
home_relative_path="notes/archive:${home_user_probe}.txt"
printf '%s\n' "$home_path_probe" >"$home_repository/$home_relative_path"
commit_then_delete "$home_repository" "$home_relative_path"
assert_legacy_fails_without_value \
    "$home_repository" \
    home-path \
    'Concrete personal home path found in Git history' \
    "$home_user_probe"

image_user_probe="$(printf '%s%s' 'image-user-' '3075')"
image_path_probe="$(printf '/%s/%s/%s/capture.png' 'Users' "$image_user_probe" 'Desktop')"
image_repository="$(new_repository image-path)"
mkdir -p "$image_repository/assets"
image_relative_path="assets/archive:${image_user_probe}.png"
printf '\000%s\000' "$image_path_probe" >"$image_repository/$image_relative_path"
commit_then_delete "$image_repository" "$image_relative_path"
assert_legacy_fails_without_value \
    "$image_repository" \
    image-path \
    'Potential secret or personal path found in tracked or historical image metadata' \
    "$image_user_probe"

video_probe="$(printf '%s%s' 'ghp_' 'P0O9I8U7Y6T5R4E3W2Q1')"
video_repository="$(new_repository deleted-video)"
printf '\000%s\000' "$video_probe" >"$video_repository/private.mp4"
commit_then_delete "$video_repository" private.mp4
assert_legacy_fails_without_value \
    "$video_repository" \
    deleted-video \
    'Potential secret or personal path found in tracked or historical image metadata' \
    "$video_probe"

worktree_image_probe="$(printf '%s%s' 'ghp_' 'M1N2B3V4C5X6Z7L8K9J0')"
worktree_image_repository="$(new_repository worktree-image)"
printf '\000safe-image\000' >"$worktree_image_repository/current.png"
git -C "$worktree_image_repository" add current.png
git -C "$worktree_image_repository" commit -q -m "add safe image baseline"
printf '\000%s\000' "$worktree_image_probe" >"$worktree_image_repository/current.png"
assert_legacy_fails_without_value \
    "$worktree_image_repository" \
    worktree-image \
    'Potential secret or personal path found in tracked or historical image metadata' \
    "$worktree_image_probe"

symlink_probe="$(printf '%s%s' 'private-target-' '8520')"
symlink_repository="$(new_repository tracked-symlink-change)"
printf 'safe regular file\n' >"$symlink_repository/current.txt"
git -C "$symlink_repository" add current.txt
git -C "$symlink_repository" commit -q -m "add regular tracked file"
rm -f "$symlink_repository/current.txt"
ln -s "$symlink_probe" "$symlink_repository/current.txt"
run_audit "$symlink_repository" tracked-symlink-change
[[ "$last_status" != 0 ]] || fail "tracked-symlink-change unexpectedly passed"
grep -F -q 'Public-release privacy scanner failed closed' "$last_stderr" ||
    fail "tracked-symlink-change did not fail closed"
if grep -F -q -- "$symlink_probe" "$last_stdout" "$last_stderr"; then
    fail "tracked-symlink-change exposed the symlink target"
fi
pass

git_failure_repository="$(new_repository injected-git-failure)"
git_shim_directory="$temporary_root/git-shim"
mkdir -p "$git_shim_directory"
printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$1" = "grep" ]; then' \
    '    exit 73' \
    'fi' \
    'exec "$REAL_GIT" "$@"' \
    >"$git_shim_directory/git"
chmod 0755 "$git_shim_directory/git"
run_audit_with_git_shim "$git_failure_repository" injected-git-failure "$git_shim_directory"
[[ "$last_status" != 0 ]] || fail "injected-git-failure unexpectedly passed"
grep -F -q 'Git history audit could not inspect repository data' "$last_stderr" ||
    fail "injected-git-failure did not fail closed"
if grep -F -q -- "$git_failure_repository" "$last_stdout" "$last_stderr"; then
    fail "injected-git-failure exposed a repository path"
fi
pass

probe_nine="$(printf '%s%s' 'FloorFour-' 'Network')"
worktree_repository="$(new_repository worktree-change)"
printf 'safe baseline\n' >"$worktree_repository/current.txt"
git -C "$worktree_repository" add current.txt
git -C "$worktree_repository" commit -q -m "add tracked current file"
printf 'SSID=%s\n' "$probe_nine" >"$worktree_repository/current.txt"
assert_fails_without_value "$worktree_repository" worktree-change ssid "$probe_nine"

shallow_repository="$(new_repository shallow)"
git -C "$shallow_repository" rev-parse HEAD >"$(git -C "$shallow_repository" rev-parse --absolute-git-dir)/shallow"
run_audit "$shallow_repository" shallow
[[ "$last_status" != 0 ]] || fail "shallow repository unexpectedly passed"
grep -F -q 'requires a complete Git checkout' "$last_stderr" ||
    fail "shallow repository did not fail at the complete-history boundary"
pass

printf 'Public-release audit fixture tests passed: %d assertions.\n' "$assertions"
