#!/usr/bin/env bash

set -euo pipefail
set +x
set +a
unset github_token
github_token="${GH_TOKEN:-}"
export -n github_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN
umask 077
source "$(dirname "$0")/lib.sh"

release_require_execution_context

release_require_single_line RELEASE_TAG
release_require_single_line EXPECTED_COMMIT
release_require_single_line RELEASE_CONFIRMATION
release_require_single_line RELEASE_NOTES_PATH
release_require_single_line RELEASE_SOURCE_DIR
release_require_single_line RELEASE_DOWNLOAD_DIR
release_require_single_line GITHUB_REPOSITORY
release_require_single_line GITHUB_REF
release_require_single_line GITHUB_REF_NAME
release_require_env GITHUB_RUN_ATTEMPT
release_require_env RELEASE_CANDIDATE_RUN_ID
release_require_env RELEASE_CANDIDATE_RUN_ATTEMPT

[[ -n "$github_token" && "$github_token" != *$'\n'* && "$github_token" != *$'\r'* ]] || {
    release_die "The GitHub release credential is missing or malformed."
}

for command_name in git gh ruby cp cmp mktemp mv; do
    release_require_command "$command_name"
done

[[ "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    release_die "Draft release preparation is restricted to GitHub-hosted runners."
}
[[ "$GITHUB_REPOSITORY" == GGULBAE/desk-setup-switcher ]] || {
    release_die "Unexpected GitHub repository identity."
}
[[ "$RELEASE_TAG" == "v$VERSION" ]] || {
    release_die "RELEASE_TAG does not match the bundle version."
}
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
    release_die "EXPECTED_COMMIT has an invalid format."
}
[[ "$GITHUB_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] || {
    release_die "GITHUB_RUN_ATTEMPT has an invalid format."
}
[[ "$GITHUB_RUN_ID" =~ ^[1-9][0-9]*$ ]] || {
    release_die "GITHUB_RUN_ID has an invalid format."
}
[[ "$RELEASE_CANDIDATE_RUN_ID" =~ ^[1-9][0-9]*$ ]] || {
    release_die "RELEASE_CANDIDATE_RUN_ID has an invalid format."
}
[[ "$RELEASE_CANDIDATE_RUN_ID" != "$GITHUB_RUN_ID" ]] || {
    release_die "Draft preparation must restore a candidate from a separate origin run."
}
[[ "$RELEASE_CANDIDATE_RUN_ATTEMPT" == 1 ]] || {
    release_die "The draft must use the immutable workflow-attempt-1 candidate."
}
[[ "$RELEASE_CONFIRMATION" == "prepare signed draft $RELEASE_TAG" ]] || {
    release_die "The signed-draft confirmation phrase does not match."
}
[[ "$GITHUB_REF" == "refs/tags/$RELEASE_TAG" && "$GITHUB_REF_NAME" == "$RELEASE_TAG" ]] || {
    release_die "The workflow ref does not identify the exact release tag."
}
[[ "$RELEASE_NOTES_PATH" == "docs/releases/$RELEASE_TAG.md" ]] || {
    release_die "RELEASE_NOTES_PATH does not identify the pinned curated notes."
}
[[ -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || {
    release_die "RUNNER_TEMP is missing or is a symlink."
}

case "$RELEASE_SOURCE_DIR" in
    /*) source_directory="$RELEASE_SOURCE_DIR" ;;
    *) source_directory="$ROOT_DIR/$RELEASE_SOURCE_DIR" ;;
esac
case "$RELEASE_DOWNLOAD_DIR" in
    /*) download_directory="$RELEASE_DOWNLOAD_DIR" ;;
    *) download_directory="$ROOT_DIR/$RELEASE_DOWNLOAD_DIR" ;;
esac
notes_path="$ROOT_DIR/$RELEASE_NOTES_PATH"

[[ -d "$source_directory" && ! -L "$source_directory" ]] || {
    release_die "Release source directory is missing or is a symlink."
}
[[ -f "$notes_path" && ! -L "$notes_path" && -s "$notes_path" ]] || {
    release_die "Curated release notes must be one nonempty regular file."
}
release_require_absent_path "$download_directory"

download_parent="$(dirname "$download_directory")"
[[ -d "$download_parent" && ! -L "$download_parent" ]] || {
    release_die "Release download parent is missing or is a symlink."
}
resolved_root="$(cd "$ROOT_DIR" && pwd -P)"
resolved_runner_temp="$(cd "$RUNNER_TEMP" && pwd -P)"
resolved_download="$(cd "$download_parent" && pwd -P)/$(basename "$download_directory")"
case "$resolved_download" in
    "$resolved_root"/*|"$resolved_runner_temp"/*) ;;
    *) release_die "Release download path is outside the checkout and runner temporary directory." ;;
esac

repository_root="$(git rev-parse --show-toplevel)" || {
    release_die "The release checkout root could not be resolved."
}
[[ "$(cd "$repository_root" && pwd -P)" == "$resolved_root" ]] || {
    release_die "The release checkout root is unexpected."
}
origin_url="$(git remote get-url origin)" || release_die "The origin URL could not be read."
case "$origin_url" in
    https://github.com/GGULBAE/desk-setup-switcher|https://github.com/GGULBAE/desk-setup-switcher.git|git@github.com:GGULBAE/desk-setup-switcher.git) ;;
    *) release_die "The origin URL does not identify the expected repository." ;;
esac
git check-ref-format --allow-onelevel "$RELEASE_TAG" >/dev/null || {
    release_die "RELEASE_TAG is not a valid tag name."
}
git show-ref --verify --quiet "refs/tags/$RELEASE_TAG" || {
    release_die "The local release tag is missing."
}
tag_commit="$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}")" || {
    release_die "The local release tag commit could not be resolved."
}
tag_object="$(git rev-parse "refs/tags/$RELEASE_TAG")" || {
    release_die "The local release tag object could not be resolved."
}
checkout_commit="$(git rev-parse HEAD)" || release_die "The checkout commit could not be resolved."
[[ "$tag_object" =~ ^[0-9a-f]{40}$ ]] || release_die "The local release tag object is invalid."
[[ "$tag_commit" == "$EXPECTED_COMMIT" && "$checkout_commit" == "$EXPECTED_COMMIT" ]] || {
    release_die "The local tag, checkout, and expected commit differ."
}
tracked_notes="$(git ls-files --error-unmatch -- "$RELEASE_NOTES_PATH")" || {
    release_die "Curated release notes are not tracked."
}
[[ "$tracked_notes" == "$RELEASE_NOTES_PATH" ]] || {
    release_die "Curated release notes did not resolve to one exact tracked path."
}
if ! checkout_status="$(git status --porcelain=v1 --untracked-files=all)"; then
    release_die "The release checkout status could not be read."
fi
[[ -z "$checkout_status" ]] || {
    release_die "The release checkout is not clean."
}

dmg_name="Desk-Setup-Switcher-$VERSION.dmg"
asset_names=(
    "$dmg_name"
    "$dmg_name.sha256"
    "Desk-Setup-Switcher-$VERSION.spdx.json"
    release-manifest.json
    notary-result.json
    notary-log.json
    "Desk-Setup-Switcher-$VERSION.provenance.sigstore.json"
    "Desk-Setup-Switcher-$VERSION.sbom.sigstore.json"
    release-manifest.provenance.sigstore.json
)

ruby -e '
  directory = ARGV.shift
  expected = ARGV
  actual = Dir.children(directory)
  abort "Release source does not contain the exact candidate asset names." unless actual.sort == expected.sort
  expected.each do |name|
    path = File.join(directory, name)
    stat = File.lstat(path)
    abort "A local candidate asset is not one regular non-symlink file." unless stat.file? && !stat.symlink?
  end
' "$source_directory" "${asset_names[@]}" || {
    release_die "The local release candidate is not the exact nine-asset set."
}

temporary_root="$(mktemp -d "$RUNNER_TEMP/desk-setup-draft-release.XXXXXX")"
candidate_snapshot="$temporary_root/candidate"
notes_snapshot="$temporary_root/release-notes.md"
initial_download="$temporary_root/initial-download"
second_download="$temporary_root/second-download"
remote_refs_path="$temporary_root/remote-tag-refs.txt"
release_response="$temporary_root/releases.json"
state_status="$temporary_root/state-status.txt"
state_assets="$temporary_root/state-assets.txt"
state_missing="$temporary_root/state-missing.txt"
state_fingerprint="$temporary_root/state-fingerprint.txt"
preupload_fingerprint="$temporary_root/preupload-fingerprint.txt"
final_fingerprint="$temporary_root/final-fingerprint.txt"
remote_error="$temporary_root/remote-command.stderr"
remote_output="$temporary_root/remote-command.stdout"
final_download_staging=""

cleanup() {
    rm -rf -- "$temporary_root"
    if [[ -n "${final_download_staging:-}" ]]; then
        rm -rf -- "$final_download_staging"
    fi
}
trap cleanup EXIT

final_download_staging="$(mktemp -d "$download_parent/.desk-setup-draft-download.XXXXXX")"

mkdir "$candidate_snapshot" "$initial_download" "$second_download"
for name in "${asset_names[@]}"; do
    cp -- "$source_directory/$name" "$candidate_snapshot/$name"
    [[ -f "$source_directory/$name" && ! -L "$source_directory/$name" ]] || {
        release_die "A local candidate asset changed while it was snapshotted."
    }
    cmp -s "$source_directory/$name" "$candidate_snapshot/$name" || {
        release_die "A local candidate asset changed while it was snapshotted."
    }
done
cp -- "$notes_path" "$notes_snapshot"
[[ -f "$notes_path" && ! -L "$notes_path" ]] || {
    release_die "Curated release notes changed while they were snapshotted."
}
cmp -s "$notes_path" "$notes_snapshot" || {
    release_die "Curated release notes changed while they were snapshotted."
}

release_title="Desk Setup Switcher $RELEASE_TAG signed candidate"

require_remote_tag_commit() {
    local tag_ref
    tag_ref="refs/tags/$RELEASE_TAG"
    : >"$remote_refs_path"
    if ! git ls-remote --exit-code --tags origin "$tag_ref" "$tag_ref^{}" \
        >"$remote_refs_path" 2>"$remote_error"; then
        release_die "The release tag could not be read from origin."
    fi
    ruby -e '
      expected_commit, expected_object, tag, path = ARGV
      direct_ref = "refs/tags/#{tag}"
      peeled_ref = "#{direct_ref}^{}"
      rows = File.readlines(path, chomp: true).map { |line| line.split("\t", -1) }
      abort "Remote tag response is malformed." unless rows.all? { |row| row.length == 2 && row[0].match?(/\A[0-9a-f]{40}\z/) }
      abort "Remote tag response contains an unexpected ref." unless rows.all? { |row| [direct_ref, peeled_ref].include?(row[1]) }
      direct = rows.select { |row| row[1] == direct_ref }
      peeled = rows.select { |row| row[1] == peeled_ref }
      abort "Remote tag response is not unique." unless direct.length == 1 && peeled.length <= 1 && rows.length == direct.length + peeled.length
      abort "Remote direct tag object differs from the local tag object." unless direct.fetch(0).fetch(0) == expected_object
      resolved = peeled.empty? ? direct.fetch(0).fetch(0) : peeled.fetch(0).fetch(0)
      abort "Remote tag does not resolve to EXPECTED_COMMIT." unless resolved == expected_commit
    ' "$EXPECTED_COMMIT" "$tag_object" "$RELEASE_TAG" "$remote_refs_path" || {
        release_die "The remote release tag does not resolve uniquely to EXPECTED_COMMIT."
    }
}

read_release_state() {
    : >"$release_response"
    if ! GH_TOKEN="$github_token" gh api \
        --method GET \
        --paginate \
        --slurp \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "/repos/$GITHUB_REPOSITORY/releases?per_page=100" \
        >"$release_response" 2>"$remote_error"; then
        release_die "The GitHub release list could not be read."
    fi
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json \
        --json "$release_response" >/dev/null || {
        release_die "The GitHub release list is not strict JSON."
    }

    ruby -rjson -e '
      begin
        input, notes_path, tag, title, status_path, assets_path, missing_path, fingerprint_path, *expected = ARGV
        pages = JSON.parse(File.binread(input), allow_nan: false)
        raise "release list is not a paginated array" unless pages.is_a?(Array) && pages.all? { |page| page.is_a?(Array) }
        releases = pages.flatten(1)
        raise "release list contains a non-object" unless releases.all? { |release| release.is_a?(Hash) }
        raise "release list contains an invalid tag name" unless releases.all? { |release| release["tag_name"].is_a?(String) }
        matches = releases.select { |release| release["tag_name"] == tag }
        raise "release tag is duplicated" if matches.length > 1

        if matches.empty?
          File.binwrite(status_path, "absent\n")
          File.binwrite(assets_path, "")
          File.binwrite(missing_path, expected.join("\n") + "\n")
          File.binwrite(fingerprint_path, "absent\n")
          exit 0
        end

        release = matches.fetch(0)
        notes = File.binread(notes_path).force_encoding(Encoding::UTF_8)
        raise "release notes are not UTF-8" unless notes.valid_encoding?
        raise "release id is invalid" unless release["id"].is_a?(Integer) && release["id"].positive?
        raise "release is not an unpublished draft prerelease" unless release["draft"] == true && release["prerelease"] == true && release["published_at"].nil?
        raise "release title differs" unless release["name"] == title
        raise "release notes differ" unless release["body"] == notes
        assets = release["assets"]
        raise "release assets are not an array" unless assets.is_a?(Array)
        normalized = assets.map do |asset|
          raise "release asset is not an object" unless asset.is_a?(Hash)
          id = asset["id"]
          name = asset["name"]
          size = asset["size"]
          updated_at = asset["updated_at"]
          raise "release asset id is invalid" unless id.is_a?(Integer) && id.positive?
          raise "release asset name is invalid" unless name.is_a?(String) && expected.include?(name)
          raise "release asset is not uploaded" unless asset["state"] == "uploaded"
          raise "release asset size is invalid" unless size.is_a?(Integer) && size >= 0
          raise "release asset timestamp is invalid" unless updated_at.is_a?(String) && !updated_at.empty?
          [name, id, size, updated_at]
        end
        names = normalized.map(&:first)
        ids = normalized.map { |asset| asset.fetch(1) }
        raise "release asset name is duplicated" unless names.uniq.length == names.length
        raise "release asset id is duplicated" unless ids.uniq.length == ids.length
        missing = expected - names
        sorted = normalized.sort_by(&:first)
        File.binwrite(status_path, "existing\n")
        File.binwrite(assets_path, names.sort.join("\n") + (names.empty? ? "" : "\n"))
        File.binwrite(missing_path, missing.join("\n") + (missing.empty? ? "" : "\n"))
        fingerprint = [[release.fetch("id"), tag, title, "draft", "prerelease", "unpublished"].join("\t")]
        fingerprint.concat(sorted.map { |asset| asset.join("\t") })
        File.binwrite(fingerprint_path, fingerprint.join("\n") + "\n")
      rescue JSON::ParserError, KeyError, RuntimeError => error
        warn "Release state validation failed: #{error.message}"
        exit 1
      end
    ' "$release_response" "$notes_snapshot" "$RELEASE_TAG" "$release_title" \
        "$state_status" "$state_assets" "$state_missing" "$state_fingerprint" \
        "${asset_names[@]}" || release_die "The GitHub draft release state is invalid."
}

require_existing_state() {
    [[ "$(tr -d '\n' <"$state_status")" == existing ]] || {
        release_die "The expected GitHub draft release is absent."
    }
}

require_complete_state() {
    require_existing_state
    [[ ! -s "$state_missing" ]] || {
        release_die "The GitHub draft release does not contain the exact nine assets."
    }
}

download_and_compare_state() {
    local destination="$1"
    [[ -d "$destination" && ! -L "$destination" ]] || {
        release_die "A release download staging directory is invalid."
    }
    [[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
        release_die "A release download staging directory is not empty."
    }
    if [[ -s "$state_assets" ]]; then
        GH_TOKEN="$github_token" gh release download "$RELEASE_TAG" \
            --repo "$GITHUB_REPOSITORY" \
            --dir "$destination" \
            >"$remote_output" 2>"$remote_error" || release_die "Existing draft assets could not be downloaded."
    fi
    ruby -e '
      directory, expected_path = ARGV
      expected = File.readlines(expected_path, chomp: true)
      actual = Dir.children(directory)
      abort "Downloaded asset names differ from the observed release state." unless actual.sort == expected.sort
      actual.each do |name|
        stat = File.lstat(File.join(directory, name))
        abort "A downloaded asset is not one regular non-symlink file." unless stat.file? && !stat.symlink?
      end
    ' "$destination" "$state_assets" || release_die "Downloaded draft assets are structurally invalid."
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        cmp -s "$candidate_snapshot/$name" "$destination/$name" || {
            release_die "An existing draft asset differs from the exact local candidate: $name"
        }
    done <"$state_assets"
}

require_remote_tag_commit
read_release_state

if [[ "$(tr -d '\n' <"$state_status")" == absent ]]; then
    require_remote_tag_commit
    GH_TOKEN="$github_token" gh release create "$RELEASE_TAG" \
        --repo "$GITHUB_REPOSITORY" \
        --draft \
        --prerelease \
        --verify-tag \
        --notes-file "$notes_snapshot" \
        --title "$release_title" \
        >"$remote_output" 2>"$remote_error" || release_die "The empty draft prerelease could not be created."
    read_release_state
fi

require_existing_state
download_and_compare_state "$initial_download"

# Re-observe immediately before the only resumable mutation. If another actor
# added an asset, it must also match the exact candidate before this run proceeds.
require_remote_tag_commit
read_release_state
require_existing_state
cp -- "$state_fingerprint" "$preupload_fingerprint"
rm -rf -- "$second_download"
mkdir "$second_download"
download_and_compare_state "$second_download"
read_release_state
require_existing_state
cmp -s "$preupload_fingerprint" "$state_fingerprint" || {
    release_die "The draft release changed during the pre-upload comparison."
}

if [[ -s "$state_missing" ]]; then
    missing_paths=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        missing_paths+=("$candidate_snapshot/$name")
    done <"$state_missing"
    [[ "${#missing_paths[@]}" -gt 0 ]] || release_die "The missing release asset list is invalid."
    require_remote_tag_commit
    GH_TOKEN="$github_token" gh release upload "$RELEASE_TAG" "${missing_paths[@]}" \
        --repo "$GITHUB_REPOSITORY" \
        >"$remote_output" 2>"$remote_error" || release_die "Missing draft assets could not be uploaded additively."
fi

require_remote_tag_commit
read_release_state
require_complete_state
cp -- "$state_fingerprint" "$final_fingerprint"
download_and_compare_state "$final_download_staging"

# Asset IDs, sizes, timestamps, and release metadata must remain anchored while
# the complete set is downloaded. Content replacement therefore cannot hide
# behind an unchanged asset name.
read_release_state
require_complete_state
cmp -s "$final_fingerprint" "$state_fingerprint" || {
    release_die "The draft release changed while final assets were downloaded."
}
require_remote_tag_commit

mv -- "$final_download_staging" "$download_directory"
final_download_staging=""

printf 'Prepared the exact additive-only draft prerelease and redownloaded all nine assets.\n'
