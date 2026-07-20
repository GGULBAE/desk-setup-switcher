#!/usr/bin/env bash

set -euo pipefail
set +x
set +a
umask 077

# Keep the credential out of every child process except the scoped read-only
# GitHub API helper below. In particular, dirname is the first child process
# this script starts, so isolation must happen before sourcing lib.sh.
github_token="${GH_TOKEN:-}"
unset GH_TOKEN GITHUB_TOKEN GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN \
    GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR
export -n github_token 2>/dev/null || true
source "$(dirname "$0")/lib.sh"

case "${RELEASE_OPERATION:-}" in
    prepare-draft) protected_environment=release-candidate ;;
    publish-release) protected_environment=release-publication ;;
    *) release_die "Candidate restoration is restricted to a reviewed release operation." ;;
esac
release_require_execution_context "$protected_environment"

release_require_single_line RELEASE_CANDIDATE_RUN_ID
release_require_single_line RELEASE_CANDIDATE_ARTIFACT_ID
release_require_single_line RELEASE_CANDIDATE_ARTIFACT_SHA256
release_require_single_line RELEASE_CANDIDATE_RUN_ATTEMPT
release_require_single_line RELEASE_OPERATION
release_require_single_line RELEASE_TAG
release_require_single_line EXPECTED_COMMIT
release_require_single_line GITHUB_REPOSITORY
release_require_single_line GITHUB_REF
release_require_single_line GITHUB_REF_NAME
release_require_single_line RELEASE_SOURCE_DIR
release_require_env GITHUB_RUN_ATTEMPT

[[ -n "$github_token" && "$github_token" != *$'\n'* && "$github_token" != *$'\r'* ]] || {
    release_die "The GitHub artifact credential is missing or malformed."
}

for command_name in gh ruby mktemp shasum awk unzip mv; do
    release_require_command "$command_name"
done

[[ "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    release_die "Candidate restoration is restricted to GitHub-hosted runners."
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
[[ "$RELEASE_CANDIDATE_RUN_ID" =~ ^[1-9][0-9]*$ ]] || {
    release_die "RELEASE_CANDIDATE_RUN_ID must be a positive integer."
}
[[ "$RELEASE_CANDIDATE_ARTIFACT_ID" =~ ^[1-9][0-9]*$ ]] || {
    release_die "RELEASE_CANDIDATE_ARTIFACT_ID must be a positive integer."
}
[[ "$RELEASE_CANDIDATE_ARTIFACT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    release_die "RELEASE_CANDIDATE_ARTIFACT_SHA256 must be one lowercase SHA-256 digest."
}
[[ "$RELEASE_CANDIDATE_RUN_ATTEMPT" == 1 ]] || {
    release_die "The restored candidate must originate from workflow attempt 1."
}
[[ "$RELEASE_OPERATION" == prepare-draft || "$RELEASE_OPERATION" == publish-release ]] || {
    release_die "Candidate restoration is restricted to a reviewed release operation."
}
[[ "$GITHUB_RUN_ID" =~ ^[1-9][0-9]*$ && "$GITHUB_RUN_ATTEMPT" =~ ^[1-9][0-9]*$ ]] || {
    release_die "The current workflow run identity is invalid."
}
[[ "$GITHUB_RUN_ID" != "$RELEASE_CANDIDATE_RUN_ID" ]] || {
    release_die "Candidate restoration must run separately from the origin build."
}
[[ "$GITHUB_REF" == "refs/tags/$RELEASE_TAG" && "$GITHUB_REF_NAME" == "$RELEASE_TAG" ]] || {
    release_die "The workflow ref does not identify the exact release tag."
}
[[ -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || {
    release_die "RUNNER_TEMP is missing or is a symlink."
}

case "$RELEASE_SOURCE_DIR" in
    /*) requested_source_directory="$RELEASE_SOURCE_DIR" ;;
    *) requested_source_directory="$ROOT_DIR/$RELEASE_SOURCE_DIR" ;;
esac
release_require_absent_path "$requested_source_directory"

source_parent="$(dirname "$requested_source_directory")"
source_name="$(basename "$requested_source_directory")"
[[ "$source_name" != . && "$source_name" != .. && -n "$source_name" ]] || {
    release_die "RELEASE_SOURCE_DIR has an invalid final path component."
}
[[ -d "$source_parent" && ! -L "$source_parent" ]] || {
    release_die "The candidate destination parent is missing or is a symlink."
}
resolved_root="$(cd "$ROOT_DIR" && pwd -P)"
resolved_runner_temp="$(cd "$RUNNER_TEMP" && pwd -P)"
resolved_source_parent="$(cd "$source_parent" && pwd -P)"
source_directory="$resolved_source_parent/$source_name"
case "$source_directory" in
    "$resolved_root"/*|"$resolved_runner_temp"/*) ;;
    *) release_die "RELEASE_SOURCE_DIR is outside the checkout and runner temporary directory." ;;
esac
release_require_absent_path "$source_directory"

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
artifact_name="desk-setup-switcher-$RELEASE_TAG-signed-candidate-$RELEASE_CANDIDATE_RUN_ID-attempt-1"

temporary_root="$(mktemp -d "$RUNNER_TEMP/desk-setup-candidate-restore.XXXXXX")"
run_response="$temporary_root/origin-run.json"
artifact_response="$temporary_root/artifact.json"
jobs_response="$temporary_root/origin-jobs.json"
archive_path="$temporary_root/candidate.zip"
archive_inventory="$temporary_root/archive-inventory.json"
repository_id_path="$temporary_root/repository-id.txt"
artifact_size_path="$temporary_root/artifact-size.txt"
remote_error="$temporary_root/remote-command.stderr"
parse_error="$temporary_root/parse.stderr"
gh_config_directory="$temporary_root/gh-config"
staging_directory=""

cleanup() {
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    rm -rf -- "$temporary_root"
    if [[ -n "${staging_directory:-}" ]]; then
        rm -rf -- "$staging_directory"
    fi
}
trap cleanup EXIT
release_install_exit_signal_traps
mkdir -m 0700 "$gh_config_directory"

github_api_to_file() {
    local endpoint="$1"
    local destination="$2"
    : >"$destination"
    : >"$remote_error"
    if ! GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$github_token" 90 gh api \
        --hostname github.com \
        --method GET \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$endpoint" >"$destination" 2>"$remote_error"; then
        release_die "A required GitHub Actions record could not be read."
    fi
}

github_api_to_file \
    "/repos/$GITHUB_REPOSITORY/actions/runs/$RELEASE_CANDIDATE_RUN_ID" \
    "$run_response"

if ! ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json \
    --json "$run_response" >/dev/null 2>"$parse_error"; then
    release_die "The origin workflow run is not strict JSON."
fi

if ! ruby -rjson -e '
  begin
    input, run_id_text, expected_commit, repository, tag, repository_id_path = ARGV
    run_id = Integer(run_id_text, 10)
    run = JSON.parse(File.binread(input), allow_nan: false)
    raise unless run.is_a?(Hash)
    raise unless run["id"] == run_id
    workflow_path, separator, workflow_ref = run["path"].to_s.partition("@")
    raise unless workflow_path == ".github/workflows/release.yml"
    raise unless separator.empty? || [tag, "refs/tags/#{tag}"].include?(workflow_ref)
    raise unless run["event"] == "workflow_dispatch"
    raise unless run["status"] == "completed" && run["conclusion"] == "success"
    raise unless run["run_attempt"] == 1
    raise unless run["head_sha"] == expected_commit
    raise unless run["head_branch"] == tag
    raise unless run.dig("head_commit", "id") == expected_commit

    repository_record = run["repository"]
    head_repository = run["head_repository"]
    raise unless repository_record.is_a?(Hash) && head_repository.is_a?(Hash)
    repository_id = repository_record["id"]
    raise unless repository_id.is_a?(Integer) && repository_id.positive?
    raise unless repository_record["full_name"] == repository
    raise unless head_repository["id"] == repository_id
    raise unless head_repository["full_name"] == repository
    File.binwrite(repository_id_path, "#{repository_id}\n")
  rescue StandardError
    exit 1
  end
' "$run_response" "$RELEASE_CANDIDATE_RUN_ID" "$EXPECTED_COMMIT" \
    "$GITHUB_REPOSITORY" "$RELEASE_TAG" "$repository_id_path" \
    >/dev/null 2>"$parse_error"; then
    release_die "The origin workflow run does not match the pinned candidate identity."
fi

repository_id=""
IFS= read -r repository_id <"$repository_id_path" || true
[[ "$repository_id" =~ ^[1-9][0-9]*$ ]] || {
    release_die "The origin repository ID is invalid."
}

github_api_to_file \
    "/repos/$GITHUB_REPOSITORY/actions/artifacts/$RELEASE_CANDIDATE_ARTIFACT_ID" \
    "$artifact_response"

if ! ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json \
    --json "$artifact_response" >/dev/null 2>"$parse_error"; then
    release_die "The artifact record is not strict JSON."
fi

if ! ruby -rjson -e '
  begin
    input, artifact_id_text, artifact_name, expected_digest, run_id_text,
      expected_commit, repository, repository_id_text, tag, size_path = ARGV
    artifact_id = Integer(artifact_id_text, 10)
    run_id = Integer(run_id_text, 10)
    repository_id = Integer(repository_id_text, 10)
    artifact = JSON.parse(File.binread(input), allow_nan: false)
    raise unless artifact.is_a?(Hash)
    raise unless artifact["id"] == artifact_id
    raise unless artifact["name"] == artifact_name
    raise unless artifact["expired"] == false
    size = artifact["size_in_bytes"]
    raise unless size.is_a?(Integer) && size.positive?
    raise unless artifact["digest"] == "sha256:#{expected_digest}"

    api_url = "https://api.github.com/repos/#{repository}/actions/artifacts/#{artifact_id}"
    raise unless artifact["url"] == api_url
    raise unless artifact["archive_download_url"] == "#{api_url}/zip"

    workflow_run = artifact["workflow_run"]
    raise unless workflow_run.is_a?(Hash)
    raise unless workflow_run["id"] == run_id
    raise unless workflow_run["repository_id"] == repository_id
    raise unless workflow_run["head_repository_id"] == repository_id
    raise unless workflow_run["head_sha"] == expected_commit
    raise unless workflow_run["head_branch"] == tag
    File.binwrite(size_path, "#{size}\n")
  rescue StandardError
    exit 1
  end
' "$artifact_response" "$RELEASE_CANDIDATE_ARTIFACT_ID" "$artifact_name" \
    "$RELEASE_CANDIDATE_ARTIFACT_SHA256" "$RELEASE_CANDIDATE_RUN_ID" \
    "$EXPECTED_COMMIT" "$GITHUB_REPOSITORY" "$repository_id" "$RELEASE_TAG" \
    "$artifact_size_path" >/dev/null 2>"$parse_error"; then
    release_die "The artifact record does not match the pinned candidate identity."
fi

github_api_to_file \
    "/repos/$GITHUB_REPOSITORY/actions/runs/$RELEASE_CANDIDATE_RUN_ID/attempts/1/jobs?per_page=100" \
    "$jobs_response"

if ! ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json \
    --json "$jobs_response" >/dev/null 2>"$parse_error"; then
    release_die "The origin job list is not strict JSON."
fi

if ! ruby -rjson -e '
  begin
    input, run_id_text, expected_commit = ARGV
    run_id = Integer(run_id_text, 10)
    response = JSON.parse(File.binread(input), allow_nan: false)
    raise unless response.is_a?(Hash)
    jobs = response["jobs"]
    raise unless jobs.is_a?(Array) && jobs.all? { |job| job.is_a?(Hash) }
    raise unless response["total_count"] == jobs.length
    matches = jobs.select { |job| job["name"] == "Build and retain signed candidate" }
    raise unless matches.length == 1
    job = matches.fetch(0)
    raise unless job["id"].is_a?(Integer) && job["id"].positive?
    # Bind the matched job twice: the attempt-specific endpoint selects
    # attempt 1, and the returned job record must independently say attempt 1.
    raise unless job["run_id"] == run_id && job["run_attempt"] == 1
    raise unless job["head_sha"] == expected_commit
    raise unless job["status"] == "completed" && job["conclusion"] == "success"
    labels = job["labels"]
    raise unless labels.is_a?(Array) && labels.all? { |label| label.is_a?(String) }
    raise unless labels.include?("macos-15") && !labels.include?("self-hosted")
    raise unless job["runner_group_name"] == "GitHub Actions"
  rescue StandardError
    exit 1
  end
' "$jobs_response" "$RELEASE_CANDIDATE_RUN_ID" "$EXPECTED_COMMIT" \
    >/dev/null 2>"$parse_error"; then
    release_die "The origin build job is not one successful GitHub-hosted candidate build."
fi

github_api_to_file \
    "/repos/$GITHUB_REPOSITORY/actions/artifacts/$RELEASE_CANDIDATE_ARTIFACT_ID/zip" \
    "$archive_path"
[[ -f "$archive_path" && ! -L "$archive_path" && -s "$archive_path" ]] || {
    release_die "The candidate artifact archive is empty or invalid."
}

artifact_size=""
IFS= read -r artifact_size <"$artifact_size_path" || true
[[ "$artifact_size" =~ ^[1-9][0-9]*$ ]] || {
    release_die "The artifact record size is invalid."
}
if ! ruby -e 'exit(File.size(ARGV.fetch(0)) == Integer(ARGV.fetch(1), 10) ? 0 : 1)' \
    "$archive_path" "$artifact_size" >/dev/null 2>"$parse_error"; then
    release_die "The downloaded artifact size differs from its GitHub record."
fi
[[ "$(release_sha256 "$archive_path")" == "$RELEASE_CANDIDATE_ARTIFACT_SHA256" ]] || {
    release_die "The downloaded artifact digest differs from its pinned digest."
}

# Parse the ZIP central directory before extraction. This rejects ZIP64,
# encryption, duplicate or nested names, symlink/directory attributes, and
# local-header name substitutions. Extraction later streams each validated
# member into a private regular file instead of trusting archive paths.
if ! ruby -rjson -e '
  begin
    archive_path, inventory_path, *expected = ARGV
    data = File.binread(archive_path)
    eocd_signature = "PK\x05\x06".b
    search_start = [data.bytesize - 65_557, 0].max
    eocd_offset = nil
    cursor = data.bytesize
    while cursor.positive? &&
        (candidate = data.rindex(eocd_signature, cursor - 1)) && candidate >= search_start
      if candidate + 22 <= data.bytesize
        comment_length = data.byteslice(candidate + 20, 2).unpack1("v")
        if candidate + 22 + comment_length == data.bytesize
          eocd_offset = candidate
          break
        end
      end
      cursor = candidate
    end
    raise unless eocd_offset

    disk_number = data.byteslice(eocd_offset + 4, 2).unpack1("v")
    central_disk = data.byteslice(eocd_offset + 6, 2).unpack1("v")
    entries_on_disk = data.byteslice(eocd_offset + 8, 2).unpack1("v")
    entry_count = data.byteslice(eocd_offset + 10, 2).unpack1("v")
    central_size = data.byteslice(eocd_offset + 12, 4).unpack1("V")
    central_offset = data.byteslice(eocd_offset + 16, 4).unpack1("V")
    raise unless disk_number.zero? && central_disk.zero?
    raise unless entries_on_disk == entry_count && entry_count == expected.length
    raise if [entries_on_disk, entry_count].include?(0xffff)
    raise if [central_size, central_offset].include?(0xffffffff)
    raise unless central_offset + central_size == eocd_offset

    entries = []
    position = central_offset
    entry_count.times do
      raise unless data.byteslice(position, 4) == "PK\x01\x02".b
      raise unless position + 46 <= eocd_offset
      version_made_by = data.byteslice(position + 4, 2).unpack1("v")
      flags = data.byteslice(position + 8, 2).unpack1("v")
      method = data.byteslice(position + 10, 2).unpack1("v")
      compressed_size = data.byteslice(position + 20, 4).unpack1("V")
      uncompressed_size = data.byteslice(position + 24, 4).unpack1("V")
      name_length = data.byteslice(position + 28, 2).unpack1("v")
      extra_length = data.byteslice(position + 30, 2).unpack1("v")
      comment_length = data.byteslice(position + 32, 2).unpack1("v")
      disk_start = data.byteslice(position + 34, 2).unpack1("v")
      external_attributes = data.byteslice(position + 38, 4).unpack1("V")
      local_offset = data.byteslice(position + 42, 4).unpack1("V")
      record_size = 46 + name_length + extra_length + comment_length
      raise unless position + record_size <= eocd_offset
      name = data.byteslice(position + 46, name_length)
      raise unless name && expected.include?(name)
      raise unless disk_start.zero?
      raise unless (flags & 1).zero?
      raise unless [0, 8].include?(method)
      raise if [compressed_size, uncompressed_size, local_offset].include?(0xffffffff)
      raise if (external_attributes & 0x10) != 0
      host_os = version_made_by >> 8
      unix_type = (external_attributes >> 16) & 0o170000
      raise if host_os == 3 && ![0, 0o100000].include?(unix_type)
      entries << {
        "name" => name,
        "size" => uncompressed_size,
        "compressed_size" => compressed_size,
        "local_offset" => local_offset,
        "flags" => flags,
        "method" => method
      }
      position += record_size
    end
    raise unless position == eocd_offset
    names = entries.map { |entry| entry.fetch("name") }
    raise unless names.uniq.length == names.length && names.sort == expected.sort
    raise unless entries.map { |entry| entry.fetch("local_offset") }.uniq.length == entries.length

    entries.each do |entry|
      local_offset = entry.fetch("local_offset")
      raise unless local_offset + 30 <= central_offset
      raise unless data.byteslice(local_offset, 4) == "PK\x03\x04".b
      local_flags = data.byteslice(local_offset + 6, 2).unpack1("v")
      local_method = data.byteslice(local_offset + 8, 2).unpack1("v")
      local_compressed_size = data.byteslice(local_offset + 18, 4).unpack1("V")
      local_uncompressed_size = data.byteslice(local_offset + 22, 4).unpack1("V")
      local_name_length = data.byteslice(local_offset + 26, 2).unpack1("v")
      local_extra_length = data.byteslice(local_offset + 28, 2).unpack1("v")
      local_name = data.byteslice(local_offset + 30, local_name_length)
      data_offset = local_offset + 30 + local_name_length + local_extra_length
      raise unless local_flags == entry.fetch("flags")
      raise unless local_method == entry.fetch("method")
      raise unless local_name == entry.fetch("name")
      unless (local_flags & 8) != 0
        raise unless local_compressed_size == entry.fetch("compressed_size")
        raise unless local_uncompressed_size == entry.fetch("size")
      end
      raise unless data_offset + entry.fetch("compressed_size") <= central_offset
    end

    File.binwrite(
      inventory_path,
      JSON.generate(entries.to_h { |entry| [entry.fetch("name"), entry.fetch("size")] }) + "\n"
    )
  rescue StandardError
    exit 1
  end
' "$archive_path" "$archive_inventory" "${asset_names[@]}" \
    >/dev/null 2>"$parse_error"; then
    release_die "The candidate archive is not the exact safe nine-asset ZIP."
fi

staging_directory="$(mktemp -d "$resolved_source_parent/.desk-setup-candidate-staging.XXXXXX")"
for name in "${asset_names[@]}"; do
    if ! unzip -qq -p "$archive_path" "$name" >"$staging_directory/$name" 2>"$parse_error"; then
        release_die "A candidate archive member could not be extracted."
    fi
    [[ -f "$staging_directory/$name" && ! -L "$staging_directory/$name" ]] || {
        release_die "An extracted candidate asset is not one regular file."
    }
done

if ! ruby -rjson -e '
  begin
    inventory_path, directory, *expected = ARGV
    inventory = JSON.parse(File.binread(inventory_path), allow_nan: false)
    raise unless inventory.is_a?(Hash) && inventory.keys.sort == expected.sort
    raise unless Dir.children(directory).sort == expected.sort
    expected.each do |name|
      stat = File.lstat(File.join(directory, name))
      raise unless stat.file? && !stat.symlink?
      raise unless stat.size == inventory.fetch(name)
    end
  rescue StandardError
    exit 1
  end
' "$archive_inventory" "$staging_directory" "${asset_names[@]}" \
    >/dev/null 2>"$parse_error"; then
    release_die "The extracted candidate is not the exact archive inventory."
fi

release_require_absent_path "$source_directory"
if ! mv -- "$staging_directory" "$source_directory" 2>"$parse_error"; then
    release_die "The verified candidate could not be retained atomically."
fi
staging_directory=""

printf 'Restored exact signed candidate from origin run %s.\n' "$RELEASE_CANDIDATE_RUN_ID"
