#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"
assertions=0

pass() {
    assertions=$((assertions + 1))
}

fail() {
    release_die "$1"
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-candidate-restore-tests.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mock_bin="$temporary_root/mock-bin"
mkdir "$mock_bin"
real_ruby="$(command -v ruby)"
runtime_gh_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_github_alias_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_lowercase_alias_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_gh_token_sha256="$(printf '%s' "$runtime_gh_token" | shasum -a 256 | awk '{print $1}')"

cat >"$mock_bin/dirname" <<'MOCK_DIRNAME'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:dirname\n' >&2
    exit 70
fi
printf 'dirname\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/dirname "$@"
MOCK_DIRNAME

cat >"$mock_bin/basename" <<'MOCK_BASENAME'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:basename\n' >&2
    exit 71
fi
printf 'basename\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/basename "$@"
MOCK_BASENAME

cat >"$mock_bin/mktemp" <<'MOCK_MKTEMP'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:mktemp\n' >&2
    exit 72
fi
printf 'mktemp\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/mktemp "$@"
MOCK_MKTEMP

cat >"$mock_bin/ruby" <<'MOCK_RUBY'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:ruby\n' >&2
    exit 73
fi
printf 'ruby\n' >>"$MOCK_CHILD_LOG"
exec "$MOCK_REAL_RUBY" "$@"
MOCK_RUBY

cat >"$mock_bin/shasum" <<'MOCK_SHASUM'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:shasum\n' >&2
    exit 74
fi
printf 'shasum\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/shasum "$@"
MOCK_SHASUM

cat >"$mock_bin/awk" <<'MOCK_AWK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:awk\n' >&2
    exit 75
fi
printf 'awk\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/awk "$@"
MOCK_AWK

cat >"$mock_bin/unzip" <<'MOCK_UNZIP'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:unzip\n' >&2
    exit 76
fi
printf 'unzip\n' >>"$MOCK_CHILD_LOG"
exec /usr/bin/unzip "$@"
MOCK_UNZIP

cat >"$mock_bin/mv" <<'MOCK_MV'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'CREDENTIAL_LEAK:mv\n' >&2
    exit 77
fi
printf 'mv\n' >>"$MOCK_CHILD_LOG"
exec /bin/mv "$@"
MOCK_MV

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

received_token="${GH_TOKEN:-}"
unset GH_TOKEN
received_token_sha256="$(printf '%s' "$received_token" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
unset received_token
[[ "$received_token_sha256" == "$MOCK_EXPECTED_GH_TOKEN_SHA256" ]] || {
    printf 'The mock gh credential is missing.\n' >&2
    exit 78
}
[[ -z "${GITHUB_TOKEN+x}" && -z "${github_token+x}" ]] || {
    printf 'An unintended GitHub credential reached gh.\n' >&2
    exit 79
}
printf 'gh-authenticated\n' >>"$MOCK_CHILD_LOG"
printf '%q ' "$@" >>"$MOCK_COMMAND_LOG"
printf '\n' >>"$MOCK_COMMAND_LOG"

[[ "$#" == 10 && "$1" == api && "$2" == --hostname && "$3" == github.com \
    && "$4" == --method && "$5" == GET \
    && "$6" == -H && "$7" == "Accept: application/vnd.github+json" \
    && "$8" == -H && "$9" == "X-GitHub-Api-Version: 2022-11-28" ]] || exit 80
endpoint="${10}"

emit_failure() {
    printf '{"private_remote_response":"SENSITIVE_REMOTE_MARKER"}\n'
    printf 'SENSITIVE_REMOTE_MARKER\n' >&2
    exit 81
}

case "$endpoint" in
    "/repos/GGULBAE/desk-setup-switcher/actions/runs/$MOCK_ORIGIN_RUN_ID")
        [[ "$MOCK_SCENARIO" != run-api-error ]] || emit_failure
        exec /bin/cat "$MOCK_RUN_RESPONSE"
        ;;
    "/repos/GGULBAE/desk-setup-switcher/actions/artifacts/$MOCK_ARTIFACT_ID")
        [[ "$MOCK_SCENARIO" != artifact-api-error ]] || emit_failure
        exec /bin/cat "$MOCK_ARTIFACT_RESPONSE"
        ;;
    "/repos/GGULBAE/desk-setup-switcher/actions/runs/$MOCK_ORIGIN_RUN_ID/attempts/1/jobs?per_page=100")
        [[ "$MOCK_SCENARIO" != jobs-api-error ]] || emit_failure
        exec /bin/cat "$MOCK_JOBS_RESPONSE"
        ;;
    "/repos/GGULBAE/desk-setup-switcher/actions/artifacts/$MOCK_ARTIFACT_ID/zip")
        [[ "$MOCK_SCENARIO" != download-api-error ]] || emit_failure
        exec /bin/cat "$MOCK_DOWNLOAD_ARCHIVE"
        ;;
    *) exit 82 ;;
esac
MOCK_GH

chmod 0755 "$mock_bin/dirname" "$mock_bin/basename" "$mock_bin/mktemp" \
    "$mock_bin/ruby" "$mock_bin/shasum" "$mock_bin/awk" "$mock_bin/unzip" \
    "$mock_bin/mv" "$mock_bin/gh"

expected_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
origin_run_id=12345
current_run_id=99999
artifact_id=67890
repository_id=456789
tag="v$VERSION"
artifact_name="desk-setup-switcher-$tag-signed-candidate-$origin_run_id-attempt-1"
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

case_index=0
case_root=""
source_directory=""
source_parent=""
expected_directory=""
child_log=""
command_log=""
archive_digest=""
download_archive=""
preexisting_destination=absent

create_test_archive() {
    local scenario="$1"
    local archive="$2"
    if [[ "$scenario" == archive-corrupt ]]; then
        printf 'not a zip SENSITIVE_REMOTE_MARKER\n' >"$archive"
        return
    fi

    "$real_ruby" -rzlib -e '
      scenario, expected_directory, output, *expected = ARGV
      entries = expected.map { |name| [name, File.binread(File.join(expected_directory, name)), 0o100644] }
      case scenario
      when "archive-traversal"
        entries[0][0] = "../#{entries[0][0]}"
      when "archive-symlink"
        entries[0][1] = expected.fetch(1)
        entries[0][2] = 0o120777
      when "archive-extra"
        entries << ["unexpected.txt", "unexpected\n", 0o100644]
      when "archive-duplicate"
        entries << entries.fetch(0).dup
      end

      local_records = +"".b
      central_records = +"".b
      entries.each do |name, body, mode|
        name = name.b
        body = body.b
        crc = Zlib.crc32(body)
        local_offset = local_records.bytesize
        local_records << [0x04034b50, 20, 0, 0, 0, 0, crc, body.bytesize, body.bytesize,
          name.bytesize, 0].pack("VvvvvvVVVvv")
        local_records << name << body
        central_records << [0x02014b50, 0x0314, 20, 0, 0, 0, 0, crc, body.bytesize,
          body.bytesize, name.bytesize, 0, 0, 0, 0, mode << 16, local_offset]
          .pack("VvvvvvvVVVvvvvvVV")
        central_records << name
      end
      central_offset = local_records.bytesize
      eocd = [0x06054b50, 0, 0, entries.length, entries.length, central_records.bytesize,
        central_offset, 0].pack("VvvvvVVv")
      File.binwrite(output, local_records + central_records + eocd)
    ' "$scenario" "$expected_directory" "$archive" "${asset_names[@]}"
}

write_api_fixtures() {
    local scenario="$1"
    "$real_ruby" -rjson -e '
      scenario, run_path, artifact_path, jobs_path, run_id_text, artifact_id_text,
        repository_id_text, commit, repository, tag, artifact_name, archive_path, digest = ARGV
      run_id = Integer(run_id_text, 10)
      artifact_id = Integer(artifact_id_text, 10)
      repository_id = Integer(repository_id_text, 10)

      run = {
        "id" => run_id,
        "path" => ".github/workflows/release.yml@#{tag}",
        "event" => "workflow_dispatch",
        "status" => "completed",
        "conclusion" => "success",
        "run_attempt" => 1,
        "head_sha" => commit,
        "head_branch" => tag,
        "head_commit" => { "id" => commit },
        "repository" => { "id" => repository_id, "full_name" => repository },
        "head_repository" => { "id" => repository_id, "full_name" => repository }
      }
      case scenario
      when "run-id-mismatch" then run["id"] += 1
      when "run-path-mismatch" then run["path"] = ".github/workflows/other.yml"
      when "run-path-ref-mismatch" then run["path"] = ".github/workflows/release.yml@main"
      when "run-event-mismatch" then run["event"] = "push"
      when "run-not-completed" then run["status"] = "in_progress"; run["conclusion"] = nil
      when "run-attempt-mismatch" then run["run_attempt"] = 2
      when "run-sha-mismatch" then run["head_sha"] = "b" * 40
      when "run-repository-mismatch" then run["repository"]["full_name"] = "attacker/repository"
      when "run-repository-id-invalid" then run["repository"]["id"] = 0
      when "run-head-branch-mismatch" then run["head_branch"] = "main"
      end

      size = File.size(archive_path)
      artifact = {
        "id" => artifact_id,
        "name" => artifact_name,
        "expired" => false,
        "size_in_bytes" => size,
        "digest" => "sha256:#{digest}",
        "url" => "https://api.github.com/repos/#{repository}/actions/artifacts/#{artifact_id}",
        "archive_download_url" => "https://api.github.com/repos/#{repository}/actions/artifacts/#{artifact_id}/zip",
        "workflow_run" => {
          "id" => run_id,
          "repository_id" => repository_id,
          "head_repository_id" => repository_id,
          "head_sha" => commit,
          "head_branch" => tag
        }
      }
      case scenario
      when "artifact-id-mismatch" then artifact["id"] += 1
      when "artifact-name-mismatch" then artifact["name"] = "wrong-name"
      when "artifact-expired" then artifact["expired"] = true
      when "artifact-zero-size" then artifact["size_in_bytes"] = 0
      when "artifact-size-mismatch" then artifact["size_in_bytes"] += 1
      when "artifact-digest-metadata-mismatch" then artifact["digest"] = "sha256:" + "b" * 64
      when "artifact-run-mismatch" then artifact["workflow_run"]["id"] += 1
      when "artifact-sha-mismatch" then artifact["workflow_run"]["head_sha"] = "b" * 40
      when "artifact-repository-mismatch" then artifact["workflow_run"]["repository_id"] += 1
      end

      job = {
        "id" => 333,
        "name" => "Build and retain signed candidate",
        "run_id" => run_id,
        "run_attempt" => 1,
        "head_sha" => commit,
        "status" => "completed",
        "conclusion" => "success",
        "labels" => ["macos-15"],
        "runner_group_name" => "GitHub Actions"
      }
      jobs = [job]
      case scenario
      when "job-missing" then job["name"] = "Another job"
      when "job-duplicate" then jobs << job.dup
      when "job-failed" then job["conclusion"] = "failure"
      when "job-self-hosted" then job["labels"] = ["self-hosted", "macos-15"]; job["runner_group_name"] = "Default"
      when "job-run-mismatch" then job["run_id"] += 1
      when "job-attempt-mismatch" then job["run_attempt"] = 2
      end

      File.binwrite(run_path, JSON.generate(run) + "\n")
      File.binwrite(artifact_path, JSON.generate(artifact) + "\n")
      File.binwrite(jobs_path, JSON.generate({ "total_count" => jobs.length, "jobs" => jobs }) + "\n")
    ' "$scenario" "$case_root/run.json" "$case_root/artifact.json" "$case_root/jobs.json" \
        "$origin_run_id" "$artifact_id" "$repository_id" "$expected_commit" \
        GGULBAE/desk-setup-switcher "$tag" "$artifact_name" "$case_root/archive.zip" \
        "$archive_digest"

    if [[ "$scenario" == run-invalid-json ]]; then
        printf '{SENSITIVE_REMOTE_MARKER\n' >"$case_root/run.json"
    fi
    case "$scenario" in
        run-duplicate-json)
            "$real_ruby" -e '
              path, id = ARGV
              source = File.binread(path)
              File.binwrite(path, source.sub(/\A\{/, %({"id":#{id},)))
            ' "$case_root/run.json" "$origin_run_id"
            ;;
        artifact-duplicate-json)
            "$real_ruby" -e '
              path, id = ARGV
              source = File.binread(path)
              File.binwrite(path, source.sub(/\A\{/, %({"id":#{id},)))
            ' "$case_root/artifact.json" "$artifact_id"
            ;;
        jobs-duplicate-json)
            "$real_ruby" -e '
              path = ARGV.fetch(0)
              source = File.binread(path)
              File.binwrite(path, source.sub(/\A\{/, %({"total_count":1,)))
            ' "$case_root/jobs.json"
            ;;
    esac
}

setup_case() {
    local scenario="$1"
    local name
    case_index=$((case_index + 1))
    case_root="$temporary_root/case-$case_index-$scenario"
    source_parent="$case_root/runner"
    source_directory="$source_parent/restored-candidate"
    expected_directory="$case_root/expected"
    child_log="$case_root/children.log"
    command_log="$case_root/commands.log"
    mkdir -p "$source_parent" "$expected_directory"
    : >"$child_log"
    : >"$command_log"
    for name in "${asset_names[@]}"; do
        printf 'exact restored candidate asset: %s\n' "$name" >"$expected_directory/$name"
    done

    create_test_archive "$scenario" "$case_root/archive.zip"
    archive_digest="$(shasum -a 256 "$case_root/archive.zip" | awk '{print $1}')"
    download_archive="$case_root/archive.zip"
    if [[ "$scenario" == download-digest-mismatch ]]; then
        cp -- "$case_root/archive.zip" "$case_root/download.zip"
        "$real_ruby" -e '
          path = ARGV.fetch(0)
          bytes = File.binread(path)
          bytes.setbyte(0, bytes.getbyte(0) ^ 1)
          File.binwrite(path, bytes)
        ' "$case_root/download.zip"
        download_archive="$case_root/download.zip"
    fi
    write_api_fixtures "$scenario"

    preexisting_destination=absent
    case "$scenario" in
        existing-destination)
            mkdir "$source_directory"
            printf 'preserve me\n' >"$source_directory/marker"
            preexisting_destination=directory
            ;;
        symlink-destination)
            ln -s "$case_root/missing-target" "$source_directory"
            preexisting_destination=symlink
            ;;
        symlink-parent)
            mkdir "$case_root/real-parent"
            ln -s "$case_root/real-parent" "$case_root/linked-parent"
            source_directory="$case_root/linked-parent/restored-candidate"
            ;;
        outside-destination)
            source_directory="$case_root/outside-parent/restored-candidate"
            mkdir "$case_root/outside-parent"
            ;;
    esac
}

run_target_with_overrides() {
    local scenario="$1"
    local candidate_attempt="$2"
    local candidate_digest="$3"
    local current_id="$4"
    local operation="${5:-prepare-draft}"
    local protected_environment="${6:-release-candidate}"
    env -i \
        "PATH=$mock_bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
        "HOME=${HOME:-/tmp}" \
        "TMPDIR=${TMPDIR:-/tmp}" \
        "DEVELOPER_DIR=$DEVELOPER_DIR" \
        DESK_SETUP_RELEASE_MUTATIONS=1 \
        GITHUB_ACTIONS=true \
        GITHUB_EVENT_NAME=workflow_dispatch \
        GITHUB_REF_TYPE=tag \
        "GITHUB_REF=refs/tags/$tag" \
        "GITHUB_REF_NAME=$tag" \
        "RELEASE_PROTECTED_ENVIRONMENT=$protected_environment" \
        GITHUB_REPOSITORY=GGULBAE/desk-setup-switcher \
        "GITHUB_RUN_ID=$current_id" \
        GITHUB_RUN_ATTEMPT=1 \
        RUNNER_ENVIRONMENT=github-hosted \
        "RUNNER_TEMP=$source_parent" \
        "GH_TOKEN=$runtime_gh_token" \
        "GITHUB_TOKEN=$runtime_github_alias_token" \
        "github_token=$runtime_lowercase_alias_token" \
        "RELEASE_CANDIDATE_RUN_ID=$origin_run_id" \
        "RELEASE_CANDIDATE_ARTIFACT_ID=$artifact_id" \
        "RELEASE_CANDIDATE_ARTIFACT_SHA256=$candidate_digest" \
        "RELEASE_CANDIDATE_RUN_ATTEMPT=$candidate_attempt" \
        "RELEASE_OPERATION=$operation" \
        "RELEASE_TAG=$tag" \
        "EXPECTED_COMMIT=$expected_commit" \
        "RELEASE_SOURCE_DIR=$source_directory" \
        "MOCK_REAL_RUBY=$real_ruby" \
        "MOCK_SCENARIO=$scenario" \
        "MOCK_ORIGIN_RUN_ID=$origin_run_id" \
        "MOCK_ARTIFACT_ID=$artifact_id" \
        "MOCK_RUN_RESPONSE=$case_root/run.json" \
        "MOCK_ARTIFACT_RESPONSE=$case_root/artifact.json" \
        "MOCK_JOBS_RESPONSE=$case_root/jobs.json" \
        "MOCK_DOWNLOAD_ARCHIVE=$download_archive" \
        "MOCK_CHILD_LOG=$child_log" \
        "MOCK_COMMAND_LOG=$command_log" \
        "MOCK_EXPECTED_GH_TOKEN_SHA256=$runtime_gh_token_sha256" \
        "$RELEASE_SCRIPTS_DIR/restore-candidate-artifact.sh"
}

run_target() {
    local scenario="$1"
    local operation=prepare-draft
    if [[ "$scenario" == wrong-operation ]]; then
        operation=publish
    fi
    run_target_with_overrides "$scenario" 1 "$archive_digest" "$current_run_id" "$operation"
}

assert_no_credential_leak() {
    local stderr_path="$1"
    if grep -F -q 'CREDENTIAL_LEAK:' "$stderr_path"; then
        fail "A GitHub credential reached a non-gh child process."
    fi
    pass
}

assert_commands_are_read_only() {
    if grep -Ev -q '^api --hostname github\.com --method GET -H Accept:\\ application/vnd\.github\+json -H X-GitHub-Api-Version:\\ 2022-11-28 /repos/GGULBAE/desk-setup-switcher/actions/' "$command_log"; then
        fail "Candidate restoration invoked a non-read-only GitHub command."
    fi
    pass
}

assert_destination_unchanged_or_absent() {
    case "$preexisting_destination" in
        absent)
            [[ ! -e "$source_directory" && ! -L "$source_directory" ]] || {
                fail "A failed restoration exposed a candidate destination."
            }
            ;;
        directory)
            [[ -f "$source_directory/marker" && "$(<"$source_directory/marker")" == "preserve me" ]] || {
                fail "A failed restoration changed the preexisting destination directory."
            }
            ;;
        symlink)
            [[ -L "$source_directory" && "$(readlink "$source_directory")" == "$case_root/missing-target" ]] || {
                fail "A failed restoration changed the preexisting destination symlink."
            }
            ;;
        *) fail "Unknown preexisting destination state." ;;
    esac
    pass
}

run_success_case() {
    local scenario="$1"
    local operation="${2:-prepare-draft}"
    local protected_environment="${3:-release-candidate}"
    local name first_child
    setup_case "$scenario"
    if ! run_target_with_overrides "$scenario" 1 "$archive_digest" "$current_run_id" \
        "$operation" "$protected_environment" >"$case_root/stdout" 2>"$case_root/stderr"; then
        sed -n '1,100p' "$case_root/stderr" >&2
        fail "Expected artifact restoration failed: $scenario"
    fi
    [[ -d "$source_directory" && ! -L "$source_directory" ]] || {
        fail "Successful restoration did not retain one candidate directory."
    }
    pass
    "$real_ruby" -e '
      directory, *expected = ARGV
      abort unless Dir.children(directory).sort == expected.sort
      expected.each do |name|
        stat = File.lstat(File.join(directory, name))
        abort unless stat.file? && !stat.symlink?
      end
    ' "$source_directory" "${asset_names[@]}" || fail "Restored candidate is not the exact nine-file set."
    pass
    for name in "${asset_names[@]}"; do
        cmp -s "$expected_directory/$name" "$source_directory/$name" || {
            fail "Restored candidate bytes differ: $name"
        }
    done
    pass
    [[ "$(wc -l <"$command_log" | tr -d '[:space:]')" == 4 ]] || {
        fail "Successful restoration did not make exactly four API reads."
    }
    pass
    first_child="$(sed -n '1p' "$child_log")"
    [[ "$first_child" == dirname ]] || fail "Credential isolation did not precede the first child process."
    pass
    for name in dirname basename mktemp ruby shasum awk unzip mv gh-authenticated; do
        grep -F -x -q -- "$name" "$child_log" || fail "The credential probe did not reach $name."
    done
    pass
    assert_no_credential_leak "$case_root/stderr"
    assert_commands_are_read_only
}

run_failure_case() {
    local scenario="$1"
    setup_case "$scenario"
    if run_target "$scenario" >"$case_root/stdout" 2>"$case_root/stderr"; then
        fail "Unsafe artifact restoration unexpectedly succeeded: $scenario"
    fi
    [[ ! -s "$case_root/stdout" ]] || fail "A failed restoration wrote to stdout: $scenario"
    pass
    assert_destination_unchanged_or_absent
    if grep -F -q 'SENSITIVE_REMOTE_MARKER' "$case_root/stdout" "$case_root/stderr"; then
        fail "A failed restoration exposed raw remote or archive content: $scenario"
    fi
    pass
    assert_no_credential_leak "$case_root/stderr"
    assert_commands_are_read_only
}

run_success_case success
run_success_case publication-success publish-release release-publication

for scenario in \
    run-id-mismatch \
    run-path-mismatch \
    run-path-ref-mismatch \
    run-event-mismatch \
    run-not-completed \
    run-attempt-mismatch \
    run-sha-mismatch \
    run-repository-mismatch \
    run-repository-id-invalid \
    run-head-branch-mismatch \
    run-api-error \
    run-invalid-json \
    run-duplicate-json \
    artifact-id-mismatch \
    artifact-name-mismatch \
    artifact-expired \
    artifact-zero-size \
    artifact-size-mismatch \
    artifact-digest-metadata-mismatch \
    artifact-run-mismatch \
    artifact-sha-mismatch \
    artifact-repository-mismatch \
    artifact-api-error \
    artifact-duplicate-json \
    download-digest-mismatch \
    download-api-error \
    job-missing \
    job-duplicate \
    job-failed \
    job-self-hosted \
    job-run-mismatch \
    job-attempt-mismatch \
    jobs-api-error \
    jobs-duplicate-json \
    wrong-operation \
    existing-destination \
    symlink-destination \
    symlink-parent \
    outside-destination \
    archive-traversal \
    archive-symlink \
    archive-extra \
    archive-duplicate \
    archive-corrupt; do
    run_failure_case "$scenario"
done

setup_case invalid-candidate-attempt
if run_target_with_overrides invalid-candidate-attempt 2 "$archive_digest" "$current_run_id" \
    >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "A candidate from a later workflow attempt was accepted."
fi
[[ ! -e "$source_directory" && ! -L "$source_directory" && ! -s "$case_root/stdout" ]] || {
    fail "Attempt validation exposed a candidate output."
}
pass
assert_no_credential_leak "$case_root/stderr"

setup_case invalid-candidate-digest
if run_target_with_overrides invalid-candidate-digest 1 \
    BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB \
    "$current_run_id" \
    >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "An uppercase candidate digest was accepted."
fi
[[ ! -e "$source_directory" && ! -L "$source_directory" && ! -s "$case_root/stdout" ]] || {
    fail "Digest validation exposed a candidate output."
}
pass
assert_no_credential_leak "$case_root/stderr"

setup_case same-run
if run_target_with_overrides same-run 1 "$archive_digest" "$origin_run_id" \
    >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "The origin build tried to restore its own artifact."
fi
[[ ! -e "$source_directory" && ! -L "$source_directory" && ! -s "$case_root/stdout" ]] || {
    fail "Same-run validation exposed a candidate output."
}
pass
assert_no_credential_leak "$case_root/stderr"

setup_case publication-wrong-environment
if run_target_with_overrides publication-wrong-environment 1 "$archive_digest" "$current_run_id" \
    publish-release release-candidate >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "Publication restoration escaped the publication environment."
fi
[[ ! -e "$source_directory" && ! -L "$source_directory" && ! -s "$case_root/stdout" ]] || {
    fail "Wrong publication environment exposed a candidate output."
}
pass
assert_no_credential_leak "$case_root/stderr"

setup_case draft-wrong-environment
if run_target_with_overrides draft-wrong-environment 1 "$archive_digest" "$current_run_id" \
    prepare-draft release-publication >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "Draft restoration escaped the candidate environment."
fi
[[ ! -e "$source_directory" && ! -L "$source_directory" && ! -s "$case_root/stdout" ]] || {
    fail "Wrong draft environment exposed a candidate output."
}
pass
assert_no_credential_leak "$case_root/stderr"

printf 'Candidate artifact restoration mock tests passed (%d assertions).\n' "$assertions"
