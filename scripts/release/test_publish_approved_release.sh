#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"
assertions=0

pass() {
    assertions=$((assertions + 1))
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-publish-release-tests.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

# Exercise publisher orchestration from an isolated final-version source tree.
# The production Git-history gate has a real-repository regression suite; this
# mock keeps only one narrow result-propagation seam for the publisher boundary.
publisher_target_root="$temporary_root/final-publisher-source"
mkdir -p "$publisher_target_root/docs/releases"
cp -R "$ROOT_DIR/scripts" "$ROOT_DIR/Config" "$publisher_target_root/"
cp "$ROOT_DIR/docs/releases/v0.1.0.md" \
    "$publisher_target_root/docs/releases/v0.1.0.md"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' \
    "$publisher_target_root/Config/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' \
    "$publisher_target_root/Config/Info.plist"
cat >>"$publisher_target_root/scripts/release/lib.sh" <<'FIXTURE_HISTORY_GATE'
release_verify_final_pre_tag_evidence_chain() {
    [[ "${MOCK_SCENARIO:-}" != evidence-history-gate-rejected ]]
}
FIXTURE_HISTORY_GATE
publisher_target="$publisher_target_root/scripts/release/publish-approved-release.sh"

mock_bin="$temporary_root/mock-bin"
mkdir "$mock_bin"
real_ruby="$(command -v ruby)"
real_git="$(command -v git)"
runtime_write_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_admin_read_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_enterprise_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_github_enterprise_token="$("$real_ruby" -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_write_token_sha256="$(printf '%s' "$runtime_write_token" | shasum -a 256 | awk '{print $1}')"
runtime_admin_read_token_sha256="$(printf '%s' "$runtime_admin_read_token" | shasum -a 256 | awk '{print $1}')"

cat >"$mock_bin/dirname" <<'MOCK_DIRNAME'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${RELEASE_ADMIN_READ_TOKEN+x}" \
   || -n "${github_token+x}" || -n "${write_token+x}" || -n "${admin_read_token+x}" \
   || -n "${GH_HOST+x}" || -n "${GH_DEBUG+x}" || -n "${DEBUG+x}" \
   || -n "${GH_ENTERPRISE_TOKEN+x}" || -n "${GITHUB_ENTERPRISE_TOKEN+x}" \
   || -n "${GH_CONFIG_DIR+x}" ]]; then
    printf 'A publication credential reached dirname.\n' >&2
    exit 70
fi
exec /usr/bin/dirname "$@"
MOCK_DIRNAME

cat >"$mock_bin/ruby" <<'MOCK_RUBY'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${RELEASE_ADMIN_READ_TOKEN+x}" \
   || -n "${github_token+x}" || -n "${write_token+x}" || -n "${admin_read_token+x}" ]]; then
    printf 'A publication credential reached ruby.\n' >&2
    exit 71
fi
if [[ "$#" == 3 && "$1" == -rtime && "$2" == -e \
   && "$3" == 'puts Time.now.utc.iso8601' ]]; then
    count_file="$MOCK_STATE_DIR/verified-time-reads"
    count="$(/bin/cat "$count_file")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    if [[ "$MOCK_SCENARIO" == approval-near-expiry-before-patch && "$count" -gt 1 ]] \
        || [[ "$MOCK_SCENARIO" == approval-near-expiry-after-controls && "$count" -gt 2 ]]; then
        exec "$MOCK_REAL_RUBY" -rtime -e \
            'puts (Time.iso8601(ARGV.fetch(0)) + 3_400).iso8601' "$MOCK_NOW"
    fi
    printf '%s\n' "$MOCK_NOW"
    exit 0
fi
if [[ "${1:-}" == */remote_controls_policy.rb ]]; then
    printf '%s\n' "$@" >"$MOCK_STATE_DIR/remote-policy.args"
    set +e
    "$MOCK_REAL_RUBY" "$@" 2>"$MOCK_STATE_DIR/remote-policy.stderr"
    status=$?
    set -e
    exit "$status"
fi
exec "$MOCK_REAL_RUBY" "$@"
MOCK_RUBY

cat >"$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${RELEASE_ADMIN_READ_TOKEN+x}" \
   || -n "${github_token+x}" || -n "${write_token+x}" || -n "${admin_read_token+x}" ]]; then
    printf 'A publication credential reached git.\n' >&2
    exit 72
fi

case "${1:-}" in
    rev-parse)
        case "${2:-}" in
            --show-toplevel) printf '%s\n' "$MOCK_ROOT_DIR" ;;
            HEAD|"refs/tags/$MOCK_TAG^{commit}") printf '%s\n' "$MOCK_EXPECTED_COMMIT" ;;
            "refs/tags/v0.0.9^{commit}") printf '%s\n' "$MOCK_PREDECESSOR_COMMIT" ;;
            "refs/tags/$MOCK_TAG") printf '%s\n' "$MOCK_TAG_OBJECT" ;;
            "refs/tags/v0.0.9") printf '%s\n' "$MOCK_PREDECESSOR_TAG_OBJECT" ;;
            "$MOCK_EXPECTED_COMMIT:.github/workflows"|"$MOCK_OBSERVED_MASTER:.github/workflows"|"$MOCK_APPROVAL_COMMIT:.github/workflows")
                if [[ "$MOCK_SCENARIO" == release-critical-drift && "$2" == "$MOCK_OBSERVED_MASTER:.github/workflows" ]]; then
                    printf '%040d\n' 39
                else
                    printf '%040d\n' 31
                fi ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release"|"$MOCK_OBSERVED_MASTER:scripts/release"|"$MOCK_APPROVAL_COMMIT:scripts/release")
                printf '%040d\n' 32 ;;
            "$MOCK_OBSERVED_MASTER:.github/workflows/signed-release-candidate.yml") printf '%s\n' "$MOCK_CANDIDATE_WORKFLOW_BLOB" ;;
            "$MOCK_OBSERVED_MASTER:.github/workflows/ci.yml") printf '%s\n' "$MOCK_CI_WORKFLOW_BLOB" ;;
            "$MOCK_OBSERVED_MASTER:.github/workflows/publish-release.yml") printf '%s\n' "$MOCK_PUBLICATION_WORKFLOW_BLOB" ;;
            "$MOCK_OBSERVED_MASTER:.github/workflows/release.yml") printf '%s\n' "$MOCK_LEGACY_WORKFLOW_BLOB" ;;
            *) exit 80 ;;
        esac
        ;;
    remote)
        [[ "$#" == 3 && "$2" == get-url && "$3" == origin ]] || exit 81
        printf 'https://github.com/GGULBAE/desk-setup-switcher.git\n'
        ;;
    check-ref-format)
        [[ "$#" == 3 && "$2" == --allow-onelevel && "$3" == "$MOCK_TAG" ]] || exit 82
        ;;
    show-ref)
        [[ "$#" == 4 && "$2" == --verify && "$3" == --quiet ]] || exit 83
        [[ "$4" == "refs/tags/$MOCK_TAG" || "$4" == refs/tags/v0.0.9 ]] || exit 83
        ;;
    ls-files)
        [[ "$#" == 4 && "$2" == --error-unmatch && "$3" == -- && "$4" == "$MOCK_NOTES_RELATIVE" ]] || exit 84
        printf '%s\n' "$MOCK_NOTES_RELATIVE"
        ;;
    status)
        [[ "$#" == 3 && "$2" == --porcelain=v1 && "$3" == --untracked-files=all ]] || exit 85
        ;;
    cat-file)
        if [[ "$#" == 3 && "$2" == -t \
            && ( "$3" == "$MOCK_TAG_OBJECT" || "$3" == "$MOCK_PREDECESSOR_TAG_OBJECT" ) ]]; then
            printf 'tag\n'
        elif [[ "$#" == 3 && "$2" == -p && "$3" == "$MOCK_TAG_OBJECT" ]]; then
            tag_evidence_digest="$MOCK_FINAL_EVIDENCE_SHA256"
            if [[ "$MOCK_SCENARIO" == final-evidence-tag-digest-mismatch ]]; then
                tag_evidence_digest="$(printf '0%.0s' {1..64})"
            fi
            printf 'object %s\ntype commit\ntag %s\ntagger Synthetic <synthetic@example.invalid> 0 +0000\n\nremote-controls-final-pre-tag-sha256: %s\n' \
                "$MOCK_EXPECTED_COMMIT" "$MOCK_TAG" "$tag_evidence_digest"
        elif [[ "$#" == 3 && "$2" == -e ]]; then
            [[ "$3" == "$MOCK_APPROVAL_COMMIT^{commit}" || "$3" == "$MOCK_OBSERVED_MASTER^{commit}" ]] || exit 86
        else
            exit 86
        fi
        ;;
    merge-base)
        [[ "$#" == 4 && "$2" == --is-ancestor ]] || exit 87
        if [[ "$3" == "$MOCK_EXPECTED_COMMIT" && "$4" == "$MOCK_OBSERVED_MASTER" ]]; then
            exit 0
        fi
        if [[ "$3" == "$MOCK_FINAL_EVIDENCE_COMMIT" && "$4" == "$MOCK_OBSERVED_MASTER" ]]; then
            exit 0
        fi
        exit 88
        ;;
    log)
        [[ "$#" == 7 && "$2" == --full-history && "$3" == --format=%H && "$4" == --reverse \
            && "$5" == "$MOCK_EXPECTED_COMMIT..$MOCK_OBSERVED_MASTER" \
            && "$6" == -- && "$7" == "$MOCK_FINAL_EVIDENCE_RELATIVE" ]] || exit 96
        printf '%s\n' "$MOCK_FINAL_EVIDENCE_COMMIT"
        if [[ "$MOCK_SCENARIO" == final-evidence-two-introductions ]]; then
            printf '%040d\n' 17
        fi
        ;;
    rev-list)
        if [[ "$#" == 3 && "$2" == --first-parent && "$3" == "$MOCK_OBSERVED_MASTER" ]]; then
            printf '%s\n' "$MOCK_OBSERVED_MASTER"
            if [[ "$MOCK_SCENARIO" != final-evidence-second-parent ]]; then
                printf '%s\n' "$MOCK_FINAL_EVIDENCE_COMMIT"
            fi
            printf '%s\n' "$MOCK_EXPECTED_COMMIT"
            exit 0
        fi
        [[ "$#" == 5 && "$2" == --parents && "$3" == -n && "$4" == 1 ]] || exit 94
        case "$5" in
            "$MOCK_APPROVAL_COMMIT")
                if [[ "$MOCK_SCENARIO" == approval-merge-commit ]]; then
                    printf '%s %s %040d\n' "$MOCK_APPROVAL_COMMIT" "$MOCK_OBSERVED_MASTER" 22
                else
                    printf '%s %s\n' "$MOCK_APPROVAL_COMMIT" "$MOCK_OBSERVED_MASTER"
                fi ;;
            "$MOCK_FINAL_EVIDENCE_COMMIT")
                printf '%s %s' "$MOCK_FINAL_EVIDENCE_COMMIT" "$MOCK_EXPECTED_COMMIT"
                if [[ "$MOCK_SCENARIO" == final-evidence-merge-introduction ]]; then
                    printf ' %040d' 18
                fi
                printf '\n' ;;
            *) exit 94 ;;
        esac
        ;;
    diff-tree)
        [[ "$#" == 6 && "$2" == --no-commit-id && "$3" == --name-status && "$4" == -r ]] || exit 95
        if [[ "$5" == "$MOCK_OBSERVED_MASTER" && "$6" == "$MOCK_APPROVAL_COMMIT" ]]; then
            printf 'A\t%s\nA\t%s\n' "$MOCK_APPROVAL_RELATIVE" "$MOCK_CONTROLS_RELATIVE"
            if [[ "$MOCK_SCENARIO" == approval-extra-path ]]; then
                printf 'M\t.github/workflows/publish-release.yml\n'
            fi
        elif [[ "$5" == "$MOCK_EXPECTED_COMMIT" && "$6" == "$MOCK_FINAL_EVIDENCE_COMMIT" ]]; then
            printf 'A\t%s\n' "$MOCK_FINAL_EVIDENCE_RELATIVE"
            if [[ "$MOCK_SCENARIO" == final-evidence-extra-path ]]; then
                printf 'M\tdocs/DISTRIBUTION.md\n'
            fi
        else
            exit 95
        fi
        ;;
    ls-tree)
        [[ "$#" == 4 && "$3" == -- ]] || exit 89
        case "$4" in
            "$MOCK_APPROVAL_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 6 "$MOCK_APPROVAL_RELATIVE" ;;
            "$MOCK_CONTROLS_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 7 "$MOCK_CONTROLS_RELATIVE" ;;
            "$MOCK_CANDIDATE_INVENTORY_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 17 "$MOCK_CANDIDATE_INVENTORY_RELATIVE" ;;
            "$MOCK_PREDECESSOR_LINEAGE_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 12 "$MOCK_PREDECESSOR_LINEAGE_RELATIVE" ;;
            "$MOCK_EXTERNAL_BETA_SET_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 13 "$MOCK_EXTERNAL_BETA_SET_RELATIVE" ;;
            "$MOCK_EXTERNAL_BETA_01_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 14 "$MOCK_EXTERNAL_BETA_01_RELATIVE" ;;
            "$MOCK_EXTERNAL_BETA_02_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 15 "$MOCK_EXTERNAL_BETA_02_RELATIVE" ;;
            "$MOCK_EXTERNAL_BETA_03_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 16 "$MOCK_EXTERNAL_BETA_03_RELATIVE" ;;
            "$MOCK_POLICY_RELATIVE")
                [[ "$2" == "$MOCK_APPROVAL_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 8 "$MOCK_POLICY_RELATIVE" ;;
            "$MOCK_CANDIDATE_MANUAL_RELATIVE") printf '100644 blob %040d\t%s\n' 9 "$MOCK_CANDIDATE_MANUAL_RELATIVE" ;;
            "$MOCK_PUBLICATION_MANUAL_RELATIVE") printf '100644 blob %040d\t%s\n' 10 "$MOCK_PUBLICATION_MANUAL_RELATIVE" ;;
            "$MOCK_FINAL_EVIDENCE_RELATIVE")
                [[ "$2" == "$MOCK_FINAL_EVIDENCE_COMMIT" ]] || exit 89
                printf '100644 blob %040d\t%s\n' 11 "$MOCK_FINAL_EVIDENCE_RELATIVE" ;;
            *) exit 89 ;;
        esac
        ;;
    show)
        [[ "$#" == 2 ]] || exit 90
        case "$2" in
            "$MOCK_APPROVAL_COMMIT:$MOCK_APPROVAL_RELATIVE") exec /bin/cat "$MOCK_APPROVAL_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_CONTROLS_RELATIVE") exec /bin/cat "$MOCK_CONTROLS_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_CANDIDATE_INVENTORY_RELATIVE") exec /bin/cat "$MOCK_CANDIDATE_INVENTORY_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_PREDECESSOR_LINEAGE_RELATIVE") exec /bin/cat "$MOCK_PREDECESSOR_LINEAGE_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_EXTERNAL_BETA_SET_RELATIVE") exec /bin/cat "$MOCK_EXTERNAL_BETA_SET_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_EXTERNAL_BETA_01_RELATIVE") exec /bin/cat "$MOCK_EXTERNAL_BETA_01_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_EXTERNAL_BETA_02_RELATIVE") exec /bin/cat "$MOCK_EXTERNAL_BETA_02_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_EXTERNAL_BETA_03_RELATIVE") exec /bin/cat "$MOCK_EXTERNAL_BETA_03_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_POLICY_RELATIVE") exec /bin/cat "$MOCK_POLICY_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_CANDIDATE_MANUAL_RELATIVE") exec /bin/cat "$MOCK_CANDIDATE_MANUAL_SOURCE" ;;
            "$MOCK_APPROVAL_COMMIT:$MOCK_PUBLICATION_MANUAL_RELATIVE") exec /bin/cat "$MOCK_PUBLICATION_MANUAL_SOURCE" ;;
            "$MOCK_FINAL_EVIDENCE_COMMIT:$MOCK_FINAL_EVIDENCE_RELATIVE")
                if [[ "$MOCK_SCENARIO" == final-evidence-blob-mismatch ]]; then
                    /bin/cat "$MOCK_FINAL_EVIDENCE_SOURCE"
                    printf ' '
                else
                    exec /bin/cat "$MOCK_FINAL_EVIDENCE_SOURCE"
                fi ;;
            "$MOCK_EXPECTED_COMMIT:$MOCK_CANDIDATE_MANUAL_RELATIVE") exec /bin/cat "$MOCK_FINAL_CANDIDATE_MANUAL_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:$MOCK_PUBLICATION_MANUAL_RELATIVE") exec /bin/cat "$MOCK_FINAL_PUBLICATION_MANUAL_SOURCE" ;;
            *) exit 90 ;;
        esac
        ;;
    ls-remote)
        if [[ "$#" == 4 && "$2" == --exit-code && "$3" == origin && "$4" == refs/heads/master ]]; then
            count_file="$MOCK_STATE_DIR/master-reads"
            count="$(cat "$count_file")"
            count=$((count + 1))
            printf '%s\n' "$count" >"$count_file"
            value="$MOCK_MASTER_COMMIT"
            if [[ "$MOCK_SCENARIO" == master-drift && "$count" -gt 1 ]]; then
                value="$(printf '%040d' 7)"
            fi
            if [[ "$MOCK_SCENARIO" == master-late-drift && "$count" -gt 2 ]]; then
                value="$(printf '%040d' 7)"
            fi
            printf '%s\trefs/heads/master\n' "$value"
            exit 0
        fi
        if [[ "$#" == 8 && "$2" == --exit-code && "$3" == --tags && "$4" == origin \
            && "$5" == "refs/tags/$MOCK_PREDECESSOR_TAG" \
            && "$6" == "refs/tags/$MOCK_PREDECESSOR_TAG^{}" \
            && "$7" == "refs/tags/$MOCK_TAG" && "$8" == "refs/tags/$MOCK_TAG^{}" ]]; then
            count_file="$MOCK_STATE_DIR/tag-reads"
            count="$(cat "$count_file")"
            count=$((count + 1))
            printf '%s\n' "$count" >"$count_file"
            value="$MOCK_TAG_OBJECT"
            if [[ "$MOCK_SCENARIO" == tag-drift && "$count" -gt 1 ]]; then
                value="$(printf '%040d' 7)"
            fi
            if [[ "$MOCK_SCENARIO" == tag-late-drift && "$count" -gt 2 ]]; then
                value="$(printf '%040d' 7)"
            fi
            predecessor_value="$MOCK_PREDECESSOR_TAG_OBJECT"
            if [[ "$MOCK_SCENARIO" == predecessor-tag-drift && "$count" -gt 1 ]] \
                || [[ "$MOCK_SCENARIO" == predecessor-tag-post-patch-drift && "$count" -gt 3 ]]; then
                predecessor_value="$(printf '%040d' 6)"
            fi
            if ! { [[ "$MOCK_SCENARIO" == predecessor-tag-delete && "$count" -gt 1 ]] \
                || [[ "$MOCK_SCENARIO" == predecessor-tag-post-patch-delete && "$count" -gt 3 ]]; }; then
                printf '%s\trefs/tags/%s\n' "$predecessor_value" "$MOCK_PREDECESSOR_TAG"
                printf '%s\trefs/tags/%s^{}\n' \
                    "$MOCK_PREDECESSOR_COMMIT" "$MOCK_PREDECESSOR_TAG"
            fi
            printf '%s\trefs/tags/%s\n' "$value" "$MOCK_TAG"
            printf '%s\trefs/tags/%s^{}\n' "$MOCK_EXPECTED_COMMIT" "$MOCK_TAG"
            exit 0
        fi
        exit 91
        ;;
    fetch)
        [[ "$#" == 5 && "$2" == --no-tags && "$3" == --quiet && "$4" == origin && "$5" == "$MOCK_MASTER_COMMIT" ]] || exit 92
        ;;
    *) exit 93 ;;
esac
MOCK_GIT

cat >"$temporary_root/mock-gh.rb" <<'MOCK_GH_RUBY'
require "digest"
require "json"
require "time"

args = ARGV
endpoint = args.last.to_s
immutable_request = endpoint.end_with?("/immutable-releases")
write_request = args.include?("PATCH")
hostname_routes = args.each_cons(2).count { |left, right| left == "--hostname" && right == "github.com" }
abort "GitHub hostname is not exact" unless hostname_routes == 1
if write_request
  abort "secret stream leak" unless $stdin.stat.chardev? && $stdin.read.empty?
end
expected_token_sha256 = ENV.fetch(
  write_request ? "MOCK_WRITE_TOKEN_SHA256" : "MOCK_ADMIN_READ_TOKEN_SHA256"
)
actual_token = ENV.delete("GH_TOKEN")
abort "wrong scoped token" unless actual_token &&
  Digest::SHA256.hexdigest(actual_token) == expected_token_sha256
actual_token = nil
%w[GITHUB_TOKEN RELEASE_ADMIN_READ_TOKEN github_token write_token admin_read_token
   GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN].each do |name|
  abort "credential environment leak" if ENV.key?(name)
end
File.open(ENV.fetch("MOCK_COMMAND_LOG"), "ab") { |file| file.puts(JSON.generate(args)) }

state_dir = ENV.fetch("MOCK_STATE_DIR")
config_dir = ENV.fetch("GH_CONFIG_DIR")
runner_root = File.dirname(state_dir)
abort "unsafe gh config directory" unless File.basename(config_dir) == "gh-config" &&
  File.dirname(config_dir).start_with?("#{runner_root}/desk-setup-release-publication.")
remote_dir = ENV.fetch("MOCK_REMOTE_ASSETS")
scenario = ENV.fetch("MOCK_SCENARIO")
tag = ENV.fetch("MOCK_TAG")
repository = "GGULBAE/desk-setup-switcher"
release_id = 7001
names = File.readlines(ENV.fetch("MOCK_EXPECTED_ASSETS"), chomp: true)
names << "unexpected.bin" if scenario == "extra-asset"

def state(state_dir)
  File.read(File.join(state_dir, "release-state")).strip
end

def release_record(state_dir, remote_dir, names, scenario, tag, repository, release_id)
  current_state = state(state_dir)
  public_state = current_state == "published"
  now = Time.iso8601(ENV.fetch("MOCK_NOW"))
  title = scenario == "title-mismatch" ? "Wrong title" : "Desk Setup Switcher #{tag} public beta"
  notes = scenario == "notes-mismatch" ? "Wrong notes\n" : File.binread(ENV.fetch("MOCK_NOTES_PATH"))
  created_at = scenario == "approval-before-draft" ? (now + 600).iso8601 : (now - 3_600).iso8601
  updated_at = if scenario == "release-updated-after-approval" && !public_state
    (now + 600).iso8601
  elsif public_state
    (now - 30).iso8601
  else
    (now - 1_850).iso8601
  end
  target_commitish = if scenario == "target-empty"
    ""
  elsif scenario == "target-drift" && public_state
    "other-branch"
  else
    "master"
  end
  published_at = if !public_state
    nil
  elsif scenario == "published-before-approval"
    (now - 120).iso8601
  elsif scenario == "published-in-future"
    (now + 600).iso8601
  else
    now.iso8601
  end
  assets = names.each_with_index.map do |name, index|
    path = File.join(remote_dir, name)
    content = File.file?(path) ? File.binread(path) : "unexpected\n"
    asset_id = 10_000 + index
    download_segment = public_state ? tag : "untagged-synthetic"
    {
      "id" => asset_id,
      "name" => name,
      "state" => "uploaded",
      "size" => content.bytesize,
      "digest" => "sha256:#{Digest::SHA256.hexdigest(content)}",
      "created_at" => (now - 1_900 + index).iso8601,
      "updated_at" => (now - 1_800 + index).iso8601,
      "url" => "https://api.github.com/repos/#{repository}/releases/assets/#{asset_id}",
      "browser_download_url" => "https://github.com/#{repository}/releases/download/#{download_segment}/#{name}"
    }
  end
  immutable = public_state && scenario != "published-mutable"
  immutable = nil if scenario == "immutable-null"
  draft = !public_state
  draft = nil if scenario == "draft-null"
  {
    "id" => scenario == "release-id-mismatch" ? release_id + 1 : release_id,
    "node_id" => "RE_synthetic_node",
    "tag_name" => tag,
    "target_commitish" => target_commitish,
    "name" => title,
    "body" => notes,
    "draft" => draft,
    "prerelease" => scenario == "post-not-prerelease" && public_state ? false : true,
    "published_at" => published_at,
    "created_at" => created_at,
    "updated_at" => updated_at,
    "immutable" => immutable,
    "url" => scenario == "release-url-mismatch" ? "https://api.github.com/repos/other/repository/releases/#{release_id}" : "https://api.github.com/repos/#{repository}/releases/#{release_id}",
    "upload_url" => scenario == "upload-url-mismatch" ? "https://uploads.github.com/repos/other/repository/releases/#{release_id}/assets{?name,label}" : "https://uploads.github.com/repos/#{repository}/releases/#{release_id}/assets{?name,label}",
    "assets_url" => "https://api.github.com/repos/#{repository}/releases/#{release_id}/assets",
    "html_url" => public_state ? "https://github.com/#{repository}/releases/tag/#{tag}" : "https://github.com/#{repository}/releases/tag/untagged-synthetic",
    "assets" => assets
  }
end

if endpoint == "/user"
  owner_id = scenario == "admin-token-owner-mismatch" ? 9_001 : 1_001
  puts JSON.generate("id" => owner_id, "login" => "GGULBAE", "type" => "User")
  exit 0
end

if endpoint == "/users/release-reviewer"
  reviewer_id = scenario == "reviewer-api-id-mismatch" ? 9_002 : 1_002
  puts JSON.generate("id" => reviewer_id, "login" => "Release-Reviewer", "type" => "User")
  exit 0
end

if endpoint == "/users/GGULBAE"
  publisher_id = scenario == "actor-api-id-mismatch" ? 9_001 : 1_001
  puts JSON.generate("id" => publisher_id, "login" => "ggulbae", "type" => "User")
  exit 0
end

approval_commit = ENV.fetch("MOCK_APPROVAL_COMMIT")
if endpoint == "/repos/#{repository}/actions/workflows/7000/runs?head_sha=#{approval_commit}&event=push&per_page=100"
  conclusion = scenario == "approval-ci-failed" ? "failure" : "success"
  run = {
    "id" => 8_201,
    "workflow_id" => 7_000,
    "check_suite_id" => 9_201,
    "run_attempt" => 1,
    "path" => ".github/workflows/ci.yml",
    "event" => "push",
    "head_branch" => "master",
    "head_sha" => approval_commit,
    "status" => "completed",
    "conclusion" => conclusion
  }
  if scenario == "approval-ci-ambiguous"
    puts JSON.generate("total_count" => 2, "items" => [run, run.merge("id" => 8_202)])
  else
    puts JSON.generate("total_count" => 1, "items" => [run])
  end
  exit 0
end

if endpoint == "/repos/#{repository}/actions/runs/8201/attempts/1/jobs?per_page=100"
  primary_conclusion = scenario == "approval-ci-job-failed" ? "failure" : "success"
  public_conclusion = scenario == "approval-public-ci-job-failed" ? "failure" : "success"
  jobs = [
    {
      "id" => 10_201,
      "run_id" => 8_201,
      "run_attempt" => 1,
      "name" => "Verify macOS app",
      "workflow_name" => "CI",
      "head_branch" => "master",
      "head_sha" => approval_commit,
      "status" => "completed",
      "conclusion" => primary_conclusion,
      "check_run_url" => "https://api.github.com/repos/#{repository}/check-runs/10201"
    },
    {
      "id" => 10_202,
      "run_id" => 8_201,
      "run_attempt" => 1,
      "name" => "Verify public site and release assets",
      "workflow_name" => "CI",
      "head_branch" => "master",
      "head_sha" => approval_commit,
      "status" => "completed",
      "conclusion" => public_conclusion,
      "check_run_url" => "https://api.github.com/repos/#{repository}/check-runs/10202"
    }
  ]
  jobs.pop if scenario == "approval-ci-job-missing"
  if scenario == "approval-ci-job-duplicate-id"
    jobs.fetch(1)["id"] = jobs.fetch(0).fetch("id")
    jobs.fetch(1)["check_run_url"] = jobs.fetch(0).fetch("check_run_url")
  end
  total_count = scenario == "approval-ci-job-float-count" ? 2.0 : jobs.length
  puts JSON.generate("total_count" => total_count, "items" => jobs)
  exit 0
end

if immutable_request
  if scenario == "admin-api-failure"
    warn "SENSITIVE_REMOTE_MARKER"
    exit 1
  end
  count_file = File.join(state_dir, "immutable-reads")
  count = Integer(File.read(count_file), 10) + 1
  File.binwrite(count_file, "#{count}\n")
  enabled = scenario != "immutable-disabled"
  enabled = false if scenario == "immutable-late-drift" && count > 2
  value = { "enabled" => enabled, "enforced_by_owner" => false }
  value["unexpected"] = true if scenario == "immutable-extra-key"
  puts JSON.generate(value)
  exit 0
end

if args.include?("PATCH")
  input_index = args.index("--input")
  abort "missing exact input" unless input_index && input_index + 1 < args.length
  request = File.binread(args.fetch(input_index + 1))
  abort "unexpected mutation body" unless request == "{\"draft\":false,\"prerelease\":true,\"make_latest\":\"false\"}\n"
  abort "wrong exact release endpoint" unless endpoint == "/repos/#{repository}/releases/#{release_id}"
  if scenario == "patch-signal-hang"
    Signal.trap("TERM", "IGNORE")
    File.binwrite(ENV.fetch("MOCK_PATCH_HANG_MARKER"), "#{Process.pid}\t#{Process.ppid}\n")
    loop { sleep 1 }
  end
  File.open(ENV.fetch("MOCK_MUTATION_LOG"), "ab") { |file| file.puts("PATCH") }
  if scenario == "patch-failure"
    warn "SENSITIVE_REMOTE_MARKER"
    exit 1
  end
  File.binwrite(File.join(state_dir, "release-state"), "published\n")
  if scenario == "post-asset-drift"
    first = File.join(remote_dir, File.readlines(ENV.fetch("MOCK_EXPECTED_ASSETS"), chomp: true).first)
    original = File.binread(first)
    File.binwrite(first, original.reverse)
  end
  if scenario == "ambiguous-success"
    warn "SENSITIVE_REMOTE_MARKER"
    exit 1
  end
  if scenario == "invalid-patch-response"
    puts "{}"
    exit 0
  end
  puts JSON.generate(release_record(state_dir, remote_dir, names, scenario, tag, repository, release_id))
  exit 0
end

if endpoint == "/repos/#{repository}/releases?per_page=100"
  if scenario == "api-failure"
    warn "SENSITIVE_REMOTE_MARKER"
    exit 1
  end
  releases = [release_record(state_dir, remote_dir, names, scenario, tag, repository, release_id)]
  if scenario == "other-release" || (scenario == "post-other-release-drift" && state(state_dir) == "published")
    other = release_record(state_dir, remote_dir, names, "complete", "v0.0.9", repository, 6999)
    other["draft"] = false
    other["published_at"] = (Time.iso8601(ENV.fetch("MOCK_NOW")) - 7_200).iso8601
    other["immutable"] = true
    releases << other
  end
  puts JSON.generate([releases])
  exit 0
end

if endpoint == "/repos/#{repository}/releases/#{release_id}"
  record = release_record(state_dir, remote_dir, names, scenario, tag, repository, release_id)
  if scenario == "final-exact-metadata-drift" && state(state_dir) == "draft"
    record["name"] = "Drifted immediately before publication"
  end
  puts JSON.generate(record)
  exit 0
end

if endpoint == "/repos/#{repository}/releases/#{release_id}/assets?per_page=100"
  release = release_record(state_dir, remote_dir, names, scenario, tag, repository, release_id)
  puts JSON.generate([release.fetch("assets")])
  exit 0
end

if (match = endpoint.match(%r{\A/repos/#{Regexp.escape(repository)}/releases/assets/([1-9][0-9]*)\z}))
  asset_id = Integer(match[1], 10)
  index = asset_id - 10_000
  abort "unknown asset ID" unless index >= 0 && index < names.length
  STDOUT.binmode
  STDOUT.write(File.binread(File.join(remote_dir, names.fetch(index))))
  exit 0
end

abort "unexpected gh invocation"
MOCK_GH_RUBY

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
exec "$MOCK_REAL_RUBY" "$MOCK_GH_RUBY" "$@"
MOCK_GH

chmod +x "$mock_bin/dirname" "$mock_bin/ruby" "$mock_bin/git" "$mock_bin/gh"

asset_names=(
    Desk-Setup-Switcher-0.1.0.dmg
    Desk-Setup-Switcher-0.1.0.dmg.sha256
    Desk-Setup-Switcher-0.1.0.spdx.json
    release-manifest.json
    notary-result.json
    notary-log.json
    Desk-Setup-Switcher-0.1.0.provenance.sigstore.json
    Desk-Setup-Switcher-0.1.0.sbom.sigstore.json
    release-manifest.provenance.sigstore.json
)
predecessor_asset_names=(
    Desk-Setup-Switcher-0.0.9.dmg
    Desk-Setup-Switcher-0.0.9.dmg.sha256
    Desk-Setup-Switcher-0.0.9.spdx.json
    release-manifest.json
    notary-result.json
    notary-log.json
    Desk-Setup-Switcher-0.0.9.provenance.sigstore.json
    Desk-Setup-Switcher-0.0.9.sbom.sigstore.json
    release-manifest.provenance.sigstore.json
)

write_approval_record() {
    local destination="$1"
    local final_dmg_sha="$2"
    local scenario="$3"
    local observed_master="$4"
    local remote_controls_sha="$5"
    local approved_at="$6"
    local release_manifest_sha="$7"
    local final_dmg_provenance_sha="$8"
    local candidate_inventory_sha="$9"
    local predecessor_lineage_sha="${10}"
    local external_beta_set_sha="${11}"
    local external_beta_01_sha="${12}"
    local external_beta_02_sha="${13}"
    local external_beta_03_sha="${14}"
    local recorded_dmg_sha="$final_dmg_sha"
    [[ "$scenario" != approval-mismatch ]] || recorded_dmg_sha="$(printf '9%.0s' {1..64})"
    "$real_ruby" -rjson -rtime -e '
      output, final_dmg_sha, observed_master, remote_controls_sha, scenario, approved_at,
        release_manifest_sha, final_dmg_provenance_sha, candidate_inventory_sha,
        predecessor_lineage_sha, external_beta_set_sha, external_beta_01_sha,
        external_beta_02_sha, external_beta_03_sha = ARGV
      now = Time.iso8601(approved_at)
      value = {
        "schemaVersion" => "desk-setup-switcher.publication-approval/v2",
        "subject" => {
          "repository" => "GGULBAE/desk-setup-switcher",
          "tag" => "v0.1.0",
          "commit" => "a" * 40,
          "remoteControlsObservedMasterCommit" => observed_master,
          "releaseId" => 7001,
          "candidateOriginRunId" => 8001,
          "candidateOriginRunAttempt" => 1,
          "candidateArtifactId" => 9001,
          "candidateArtifactSHA256" => "b" * 64,
          "finalDMGSHA256" => final_dmg_sha
        },
        "gates" => {
          "remoteControlsStable" => true,
          "signedNotarizedStapled" => true,
          "exactNineAssetsAndAttestations" => true,
          "immutableReleases" => true,
          "cleanQuarantinedLifecycle" => true,
          "threeExternalBetas" => true,
          "zeroPublicP0P1" => true,
          "zeroConfidentialP0P1" => true,
          "publicSurfaceReady" => true
        },
        "evidence" => {
          "candidateInventorySHA256" => candidate_inventory_sha,
          "releaseEvidenceSHA256" => "c" * 64,
          "cleanLifecycleSHA256" => external_beta_01_sha,
          "externalBetaSetSHA256" => external_beta_set_sha,
          "externalBetaReportSHA256" => [
            external_beta_01_sha,
            external_beta_02_sha,
            external_beta_03_sha
          ],
          "finalDMGProvenanceSHA256" => final_dmg_provenance_sha,
          "predecessorLineageSHA256" => predecessor_lineage_sha,
          "publicBlockerQuerySHA256" => "2" * 64,
          "confidentialBlockerSignoffSHA256" => "3" * 64,
          "publicSurfaceSHA256" => "4" * 64,
          "releaseManifestSHA256" => release_manifest_sha,
          "remoteControlsEvidenceSHA256" => remote_controls_sha
        },
        "approval" => {
          "decision" => "approved",
          "approvalMode" => scenario == "approval-mode-mismatch" ? "one-maintainer" : "independent-review",
          "approverLogin" => "release-reviewer",
          "publisherLogin" => "GGULBAE",
          "approvedAt" => now.iso8601,
          "expiresAt" => (now + 3_600).iso8601,
          "releasePublication" => true
        }
      }
      File.binwrite(output, JSON.generate(value) + "\n")
    ' "$destination" "$recorded_dmg_sha" "$observed_master" "$remote_controls_sha" \
        "$scenario" "$approved_at" "$release_manifest_sha" "$final_dmg_provenance_sha" \
        "$candidate_inventory_sha" "$predecessor_lineage_sha" "$external_beta_set_sha" \
        "$external_beta_01_sha" "$external_beta_02_sha" "$external_beta_03_sha"
}

run_scenario() {
    local scenario="$1"
    local expected_result="$2"
    local expected_patch_count="$3"
    if [[ -n "${PUBLISH_SCENARIO_FILTER:-}" && "$PUBLISH_SCENARIO_FILTER" != "$scenario" ]]; then
        return 0
    fi
    printf 'Approved Release publication scenario: %s\n' "$scenario" >&2
    local root="$temporary_root/$scenario"
    local runner_temp="$root/runner"
    local source_directory="$runner_temp/source"
    local predecessor_source_directory="$runner_temp/predecessor"
    local remote_directory="$runner_temp/remote"
    local download_directory="$runner_temp/download"
    local state_directory="$runner_temp/state"
    local expected_assets="$runner_temp/expected-assets.txt"
    local approval_record="$runner_temp/approval.json"
    local remote_controls_record="$runner_temp/remote-controls-pre-publication.json"
    local candidate_inventory_record="$runner_temp/candidate-inventory.json"
    local predecessor_lineage_record="$runner_temp/predecessor-lineage.json"
    local external_beta_set_record="$runner_temp/external-beta-set.json"
    local external_beta_01_record="$runner_temp/external-beta-01.json"
    local external_beta_02_record="$runner_temp/external-beta-02.json"
    local external_beta_03_record="$runner_temp/external-beta-03.json"
    local remote_controls_policy="$runner_temp/remote-controls-policy.json"
    local candidate_manual_record="$runner_temp/release-candidate-admin-bypass.json"
    local publication_manual_record="$runner_temp/release-publication-admin-token-scope.json"
    local final_candidate_manual_record="$runner_temp/final-release-candidate-admin-bypass.json"
    local final_publication_manual_record="$runner_temp/final-release-publication-admin-token-scope.json"
    local final_pre_tag_evidence_record="$runner_temp/remote-controls-final-pre-tag.json"
    local command_log="$runner_temp/commands.jsonl"
    local mutation_log="$runner_temp/mutations.txt"
    local patch_hang_marker="$runner_temp/patch-hang-marker.txt"
    local stdout_path="$runner_temp/stdout.txt"
    local stderr_path="$runner_temp/stderr.txt"
    local notes_path="$publisher_target_root/docs/releases/v0.1.0.md"
    local effective_scenario="$scenario"
    local master_commit
    local observed_master
    local mock_now
    local publication_attempt=1
    master_commit="$(printf 'd%.0s' {1..40})"
    observed_master="$(printf 'c%.0s' {1..40})"
    mock_now="$($real_ruby -rtime -e 'puts Time.now.utc.iso8601')"

    mkdir -p "$source_directory" "$remote_directory" "$state_directory"
    mkdir -m 0700 "$predecessor_source_directory"
    printf '%s\n' "${asset_names[@]}" >"$expected_assets"
    for name in "${asset_names[@]}"; do
        printf 'mock publication artifact: %s\n' "$name" >"$source_directory/$name"
        cp "$source_directory/$name" "$remote_directory/$name"
    done
    for name in "${predecessor_asset_names[@]}"; do
        printf 'mock protected predecessor artifact: %s\n' "$name" \
            >"$predecessor_source_directory/$name"
    done
    if [[ "$scenario" == predecessor-source-extra ]]; then
        printf 'unexpected predecessor file\n' >"$predecessor_source_directory/unexpected.txt"
    fi
    if [[ "$scenario" == asset-mismatch ]]; then
        first_asset="$remote_directory/${asset_names[0]}"
        "$real_ruby" -e '
          path = ARGV.fetch(0)
          bytes = File.binread(path)
          abort if bytes.empty?
          bytes.setbyte(0, bytes.getbyte(0) ^ 1)
          File.binwrite(path, bytes)
        ' "$first_asset"
    fi
    final_dmg_sha="$(shasum -a 256 "$source_directory/Desk-Setup-Switcher-0.1.0.dmg" | awk '{print $1}')"
    "$real_ruby" -rjson -rdigest -rtime -e '
      manifest_path, dmg_path, created_at_text, release_policy_path = ARGV
      require release_policy_path
      created_at = Time.iso8601(created_at_text) - 5 * 86_400
      dmg_name = File.basename(dmg_path)
      dmg_bytes = File.binread(dmg_path)
      dmg_sha = Digest::SHA256.hexdigest(dmg_bytes)
      verification_output = {
        "appCodesign" => "valid on disk\nsatisfies its designated requirement\n",
        "dmgCodesign" => "valid on disk\nsatisfies its designated requirement\n",
        "mountedAppCompatibility" => "Verified release app metadata and resources: architectures=arm64,x86_64; minos=arm64:14.0,x86_64:14.0; executable-sha256=#{"3" * 64}\n",
        "signedAppCompatibility" => "Verified release app metadata and resources: architectures=arm64,x86_64; minos=arm64:14.0,x86_64:14.0; executable-sha256=#{"3" * 64}\n",
        "spctlApp" => "accepted\nsource=Notarized Developer ID\n",
        "spctlDMG" => "accepted\nsource=Notarized Developer ID\n",
        "staplerValidate" => "The validate action worked!\n"
      }
      manifest = {
        "schemaVersion" => "desk-setup-switcher.release-evidence/v1",
        "generator" => "scripts/release/release_policy.rb",
        "release" => {
          "version" => "0.1.0",
          "tag" => "v0.1.0",
          "commit" => "a" * 40,
          "namespace" => "https://github.com/GGULBAE/desk-setup-switcher/release-evidence/v0.1.0/#{dmg_sha}",
          "created" => created_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "buildNumber" => "2",
          "run" => {
            "id" => 8001,
            "attempt" => 1,
            "url" => "https://github.com/GGULBAE/desk-setup-switcher/actions/runs/8001"
          }
        },
        "toolchain" => {
          "minimum-system-version" => "14.0",
          "swift" => "synthetic-6.0"
        },
        "application" => {
          "bundleIdentifier" => "io.github.ggullbae.DeskSetupSwitcher",
          "teamIdentifier" => "ABCDE12345",
          "authority" => "Developer ID Application: Synthetic Release (ABCDE12345)",
          "cdhashes" => { "arm64" => "1" * 40, "x86_64" => "2" * 40 },
          "executable" => {
            "name" => "DeskSetupSwitcher",
            "sha256" => "3" * 64,
            "size" => 1
          },
          "designatedRequirement" => {
            "normalized" => "designated => identifier \"io.github.ggullbae.DeskSetupSwitcher\" and certificate leaf[subject.OU] = ABCDE12345"
          },
          "effectiveEntitlements" => { "state" => "absent", "keys" => [] },
          "bundleManifest" => {
            "schemaVersion" => "desk-setup-switcher.app-bundle/v1",
            "rootName" => "Desk Setup Switcher.app",
            "entryCount" => 1,
            "canonicalSha256" => "4" * 64
          }
        },
        "lineage" => {
          "preNotaryDmg" => { "sha256" => "5" * 64, "size" => dmg_bytes.bytesize },
          "notary" => {
            "id" => "12345678-1234-4234-8234-123456789abc",
            "status" => "Accepted",
            "archiveFilename" => dmg_name,
            "submittedSha256" => "5" * 64,
            "logSha256" => "6" * 64,
            "logSize" => 1
          },
          "finalStapledDmg" => {
            "name" => dmg_name,
            "sha256" => dmg_sha,
            "size" => dmg_bytes.bytesize
          }
        },
        "verifications" => verification_output.keys.sort.map do |name|
          output = verification_output.fetch(name)
          {
            "name" => name,
            "sha256" => Digest::SHA256.hexdigest(output.b),
            "size" => output.bytesize,
            "result" => "pass",
            "output" => output
          }
        end,
        "assets" => [
          { "name" => dmg_name, "sha256" => dmg_sha, "size" => dmg_bytes.bytesize }
        ]
      }
      ReleasePolicy.validate_release_manifest_data(manifest)
      File.binwrite(manifest_path, JSON.generate(manifest) + "\n")
    ' "$source_directory/release-manifest.json" \
        "$source_directory/Desk-Setup-Switcher-0.1.0.dmg" "$mock_now" \
        "$ROOT_DIR/scripts/release/release_policy.rb"
    cp "$source_directory/release-manifest.json" "$remote_directory/release-manifest.json"
    predecessor_final_dmg_sha="$(shasum -a 256 \
        "$predecessor_source_directory/Desk-Setup-Switcher-0.0.9.dmg" | awk '{print $1}')"
    "$real_ruby" -rjson -rdigest -rtime -e '
      current_path, output_path, dmg_path, now_text, release_policy_path = ARGV
      require release_policy_path
      manifest = JSON.parse(File.binread(current_path), create_additions: false)
      release = manifest.fetch("release")
      dmg_bytes = File.binread(dmg_path)
      dmg_sha = Digest::SHA256.hexdigest(dmg_bytes)
      release["version"] = "0.0.9"
      release["tag"] = "v0.0.9"
      release["commit"] = "9" * 40
      release["created"] = (Time.iso8601(now_text) - 12 * 86_400).utc.iso8601
      release["buildNumber"] = "1"
      release["namespace"] =
        "https://github.com/GGULBAE/desk-setup-switcher/release-evidence/v0.0.9/#{dmg_sha}"
      release["run"] = {
        "id" => 7999,
        "attempt" => 1,
        "url" => "https://github.com/GGULBAE/desk-setup-switcher/actions/runs/7999"
      }
      manifest.fetch("lineage").fetch("notary")["archiveFilename"] = File.basename(dmg_path)
      manifest.fetch("lineage")["finalStapledDmg"] = {
        "name" => File.basename(dmg_path),
        "sha256" => dmg_sha,
        "size" => dmg_bytes.bytesize
      }
      manifest["assets"] = [
        { "name" => File.basename(dmg_path), "sha256" => dmg_sha, "size" => dmg_bytes.bytesize }
      ]
      ReleasePolicy.validate_release_manifest_data(manifest)
      File.binwrite(output_path, JSON.generate(manifest) + "\n")
    ' "$source_directory/release-manifest.json" \
        "$predecessor_source_directory/release-manifest.json" \
        "$predecessor_source_directory/Desk-Setup-Switcher-0.0.9.dmg" "$mock_now" \
        "$ROOT_DIR/scripts/release/release_policy.rb"
    "$real_ruby" -rjson -rdigest -rtime -e '
      inventory_path, lineage_path, set_path, beta_01_path, beta_02_path,
        beta_03_path, manifest_path, provenance_path, predecessor_manifest_path,
        predecessor_provenance_path, predecessor_dmg_path, final_dmg_sha,
        predecessor_final_dmg_sha, scenario, now_text = ARGV
      manifest_bytes = File.binread(manifest_path)
      manifest = JSON.parse(manifest_bytes, create_additions: false)
      provenance_bytes = File.binread(provenance_path)
      predecessor_manifest_bytes = File.binread(predecessor_manifest_path)
      predecessor_manifest = JSON.parse(predecessor_manifest_bytes, create_additions: false)
      predecessor_provenance_bytes = File.binread(predecessor_provenance_path)
      now = Time.iso8601(now_text)
      release = manifest.fetch("release")
      application = manifest.fetch("application")
      final_dmg = manifest.fetch("lineage").fetch("finalStapledDmg")
      release_manifest_sha = Digest::SHA256.hexdigest(manifest_bytes)
      provenance_sha = Digest::SHA256.hexdigest(provenance_bytes)
      predecessor_manifest_sha = Digest::SHA256.hexdigest(predecessor_manifest_bytes)
      predecessor_provenance_sha = Digest::SHA256.hexdigest(predecessor_provenance_bytes)
      candidate = {
        "repository" => "GGULBAE/desk-setup-switcher",
        "tag" => release.fetch("tag"),
        "commit" => release.fetch("commit"),
        "version" => release.fetch("version"),
        "buildNumber" => Integer(release.fetch("buildNumber"), 10),
        "bundleIdentifier" => application.fetch("bundleIdentifier"),
        "profileSchemaVersion" => 1,
        "candidateOriginRunId" => 8001,
        "candidateOriginRunAttempt" => 1,
        "candidateArtifactId" => 9001,
        "candidateArtifactSHA256" => "b" * 64,
        "finalDMGSHA256" => final_dmg_sha,
        "releaseManifestSHA256" => release_manifest_sha
      }
      installation_for = lambda do |manifest_value, evidence_label|
        installed_release = manifest_value.fetch("release")
        installed_application = manifest_value.fetch("application")
        {
          "destinationPath" => "/Applications/Desk Setup Switcher.app",
          "method" => "finder-drag-from-mounted-dmg",
          "copiedFromMountedDMG" => true,
          "dmgEjectedBeforeLaunch" => true,
          "launchedFromApplications" => true,
          "bundleIdentifier" => installed_application.fetch("bundleIdentifier"),
          "version" => installed_release.fetch("version"),
          "buildNumber" => Integer(installed_release.fetch("buildNumber"), 10),
          "executableSHA256" => installed_application.fetch("executable").fetch("sha256"),
          "bundleManifestSHA256" =>
            installed_application.fetch("bundleManifest").fetch("canonicalSha256"),
          "sourceBundleManifestMatched" => true,
          "installationEvidenceSHA256" => Digest::SHA256.hexdigest(evidence_label)
        }
      end
      predecessor_item = {
        "outcome" => "retained",
        "version" => "0.0.9",
        "buildNumber" => 1,
        "commit" => "9" * 40,
        "candidateOriginRunId" => 7999,
        "candidateOriginRunAttempt" => 1,
        "runConclusion" => "success",
        "completedAt" => (now - 11 * 86_400).utc.iso8601,
        "distributionState" => "protected-beta",
        "candidateArtifactId" => 8999,
        "candidateArtifactSHA256" => "7" * 64,
        "finalDMGSHA256" => predecessor_final_dmg_sha,
        "releaseManifestSHA256" => predecessor_manifest_sha
      }
      inventory_items = [predecessor_item]
      if scenario == "predecessor-build-reuse"
        inventory_items << {
          "outcome" => "not-retained",
          "version" => "0.0.10",
          "buildNumber" => 2,
          "commit" => "8" * 40,
          "candidateOriginRunId" => 7998,
          "candidateOriginRunAttempt" => 1,
          "runConclusion" => "failure",
          "completedAt" => (now - 6 * 86_400).utc.iso8601,
          "distributionState" => "not-distributed",
          "reason" => "build-failed"
        }
      end
      inventory = {
        "schemaVersion" => scenario == "candidate-inventory-schema-invalid" ?
          "desk-setup-switcher.candidate-inventory/v0" :
          "desk-setup-switcher.candidate-inventory/v1",
        "subject" => {
          "repository" => "GGULBAE/desk-setup-switcher",
          "workflowPath" => ".github/workflows/signed-release-candidate.yml",
          "operation" => "build-candidate",
          "currentCandidateRunId" => 8001,
          "currentCandidateBuildNumber" => 2
        },
        "collection" => {
          "collectedAt" => (now - 114 * 3_600).utc.iso8601,
          "reviewedAt" => (now - 108 * 3_600).utc.iso8601,
          "reviewMode" => "protected-complete-history-review",
          "reviewerRole" => "release-approver",
          "allPagesReviewed" => true,
          "sourceEvidenceSHA256" => "7" * 64
        },
        "items" => inventory_items
      }
      File.binwrite(inventory_path, JSON.generate(inventory) + "\n")
      inventory_sha = Digest::SHA256.file(inventory_path).hexdigest
      upgrade_predecessor = {
        "state" => "recorded",
        "distributionKind" => "protected-beta",
        "bundleIdentifier" => application.fetch("bundleIdentifier"),
        "version" => "0.0.9",
        "tag" => "v0.0.9",
        "buildNumber" => 1,
        "profileSchemaVersion" => 1,
        "sourceCommit" => "9" * 40,
        "candidateOriginRunId" => 7999,
        "candidateOriginRunAttempt" => 1,
        "candidateArtifactId" => 8999,
        "candidateArtifactSHA256" => "7" * 64,
        "artifactName" => File.basename(predecessor_dmg_path),
        "finalDMGSHA256" => predecessor_final_dmg_sha,
        "releaseManifestSHA256" => predecessor_manifest_sha,
        "provenanceBundleName" => File.basename(predecessor_provenance_path),
        "provenanceBundleSHA256" => predecessor_provenance_sha,
        "provenanceSubjectSHA256" => predecessor_final_dmg_sha,
        "releaseBoundaryEvidenceSHA256" => "e" * 64
      }
      if scenario == "predecessor-provenance-binding-mismatch"
        upgrade_predecessor["provenanceBundleSHA256"] = "0" * 64
      end
      lineage = {
        "schemaVersion" => "desk-setup-switcher.predecessor-lineage/v3",
        "candidate" => candidate,
        "candidateInventorySHA256" => inventory_sha,
        "upgradePredecessor" => upgrade_predecessor
      }
      File.binwrite(lineage_path, JSON.generate(lineage) + "\n")
      lineage_sha = Digest::SHA256.file(lineage_path).hexdigest

      report_codes = %w[beta-01 beta-02 beta-03]
      report_paths = [beta_01_path, beta_02_path, beta_03_path]
      reports = report_codes.each_with_index.map do |code, index|
        started_at = now - (4 - index) * 86_400
        completed_at = started_at + 3_600
        subject = candidate.merge(
          "finalDMGName" => final_dmg.fetch("name"),
          "provenanceBundleName" => "Desk-Setup-Switcher-#{candidate.fetch("version")}.provenance.sigstore.json",
          "provenanceBundleSHA256" => provenance_sha,
          "provenanceSubjectSHA256" => final_dmg_sha,
          "predecessorLineageSHA256" => lineage_sha
        )
        subject.delete("candidateOriginRunAttempt")
        subject["candidateOriginRunAttempt"] = 1
        report = {
          "schemaVersion" => "desk-setup-switcher.external-beta/v3",
          "report" => {
            "reportCode" => code,
            "startedAt" => started_at.utc.iso8601,
            "completedAt" => completed_at.utc.iso8601
          },
          "subject" => subject,
          "environment" => {
            "architecture" => "arm64",
            "macOSVersion" => index.zero? ? "14.6.1" : "15.#{index - 1}",
            "hardwareClass" => "apple-silicon",
            "cleanBasis" => index.zero? ? "clean-mac" : "clean-local-account",
            "coverageRole" => index.zero? ? "sonoma-full-lifecycle" : "additional-apple-silicon"
          },
          "independence" => {
            "externalTester" => true,
            "notReleaseOperator" => true,
            "notReleaseApprover" => true,
            "noRepositoryWriteAccess" => true,
            "noReleaseSecretAccess" => true
          },
          "acquisition" => {
            "channel" => "protected-workflow-browser",
            "browserDownloaded" => true,
            "normalArchiveExtraction" => true,
            "quarantinePresent" => true,
            "quarantineManufactured" => false,
            "quarantineRemoved" => false,
            "quarantineEvidenceSHA256" => (index + 1).to_s * 64,
            "checksumPass" => true,
            "provenancePass" => true,
            "gatekeeperPass" => true,
            "openAnywayUsed" => false,
            "installation" => installation_for.call(
              manifest,
              "synthetic candidate installation #{index}"
            )
          },
          "lifecycle" => {
            "firstLaunchPass" => true,
            "loginItemDefaultOffPass" => true,
            "threeStepFlowPass" => true,
            "stoppedBeforeApply" => true,
            "schema0MigrationPass" => true,
            "backupRecoveryPass" => true,
            "importExportPass" => true,
            "diagnosticsPass" => true,
            "uninstallPass" => true,
            "localDataRemovalPass" => true,
            "hardwareMutationPerformed" => false,
            "upgrade" => {
              "state" => "passed",
              "predecessorVersion" => upgrade_predecessor.fetch("version"),
              "predecessorBuildNumber" => upgrade_predecessor.fetch("buildNumber"),
              "predecessorFinalDMGSHA256" => upgrade_predecessor.fetch("finalDMGSHA256"),
              "predecessorReleaseManifestSHA256" =>
                upgrade_predecessor.fetch("releaseManifestSHA256"),
              "predecessorProvenanceBundleSHA256" =>
                upgrade_predecessor.fetch("provenanceBundleSHA256"),
              "predecessorAcquisition" => {
                "channel" => "protected-workflow-browser",
                "browserDownloaded" => true,
                "normalArchiveExtraction" => true,
                "quarantinePresent" => true,
                "quarantineManufactured" => false,
                "quarantineRemoved" => false,
                "quarantineEvidenceSHA256" => (index + 7).to_s * 64,
                "checksumPass" => true,
                "provenancePass" => true,
                "gatekeeperPass" => true,
                "openAnywayUsed" => false,
                "installation" => installation_for.call(
                  predecessor_manifest,
                  "synthetic predecessor installation #{index}"
                )
              },
              "profilesPreserved" => true,
              "settingsPreserved" => true,
              "selectionPreserved" => true,
              "backupsPreserved" => true,
              "loginItemConsentPreserved" => true
            }
          },
          "issues" => {
            "unresolvedP0" => 0,
            "unresolvedP1" => 0,
            "allFailuresTracked" => true,
            "blockerEvidenceSHA256" => (index + 4).to_s * 64
          },
          "attestation" => {
            "candidateIdentityConfirmed" => true,
            "privacyReviewed" => true,
            "reportComplete" => true,
            "testerAttested" => true,
            "noHardwareMutationClaim" => true
          }
        }
        report
      end
      case scenario
      when "beta-wrong-candidate"
        reports.fetch(1).fetch("subject")["commit"] = "9" * 40
      when "beta-duplicate-code"
        reports.fetch(1).fetch("report")["reportCode"] = "beta-01"
      when "beta-missing-sonoma"
        environment = reports.fetch(0).fetch("environment")
        environment["macOSVersion"] = "15.0"
        environment["coverageRole"] = "additional-apple-silicon"
      when "beta-lifecycle-failed"
        reports.fetch(1).fetch("lifecycle")["diagnosticsPass"] = false
      when "beta-quarantine-invalid"
        reports.fetch(2).fetch("acquisition")["quarantineRemoved"] = true
      when "beta-installation-failed"
        reports.fetch(1).dig("acquisition", "installation")["copiedFromMountedDMG"] = false
      when "beta-predecessor-installation-failed"
        reports.fetch(1).dig(
          "lifecycle", "upgrade", "predecessorAcquisition", "installation"
        )["launchedFromApplications"] = false
      when "beta-independent-false"
        reports.fetch(1).fetch("independence")["noRepositoryWriteAccess"] = false
      when "beta-provenance-mismatch"
        reports.fetch(2).fetch("subject")["provenanceBundleSHA256"] = "0" * 64
      end
      reports.each_with_index do |report, index|
        File.binwrite(report_paths.fetch(index), JSON.generate(report) + "\n")
      end
      report_digests = report_paths.map { |path| Digest::SHA256.file(path).hexdigest }
      set_subject = reports.fetch(0).fetch("subject")
      beta_set = {
        "schemaVersion" => "desk-setup-switcher.external-beta-set/v2",
        "subject" => set_subject,
        "reports" => report_codes.each_with_index.map do |code, index|
          { "reportCode" => code, "reportSHA256" => report_digests.fetch(index) }
        end,
        "independence" => {
          "reviewMode" => "protected-release-review",
          "reviewerRole" => "release-approver",
          "reviewedAt" => (now - 86_400).utc.iso8601,
          "protectedReviewEvidenceSHA256" => "d" * 64,
          "privateRosterBundleSHA256" => "e" * 64,
          "bindings" => report_codes.each_with_index.map do |code, index|
            {
              "reportCode" => code,
              "reportSHA256" => report_digests.fetch(index),
              "privateRosterEntryCommitmentSHA256" => (index + 7).to_s * 64
            }
          end,
          "assertions" => {
            "threeDistinctNaturalPersons" => true,
            "allExternalToReleaseTeam" => true,
            "noneIsReleaseOperator" => true,
            "noneIsReleaseApprover" => true,
            "noneHasPushReleaseEnvironmentOrSecretAccess" => true
          }
        },
        "coverage" => {
          "acceptedReportCount" => 3,
          "sonomaGateReportCode" => "beta-01",
          "allAppleSilicon" => true,
          "allSupportedOS" => true,
          "allMandatoryLifecyclePassed" => true
        },
        "createdAt" => (now - 12 * 3_600).utc.iso8601
      }
      if scenario == "beta-set-binding-mismatch"
        beta_set.fetch("independence").fetch("bindings").fetch(0)["reportSHA256"] = "0" * 64
      end
      File.binwrite(set_path, JSON.generate(beta_set) + "\n")
    ' "$candidate_inventory_record" "$predecessor_lineage_record" "$external_beta_set_record" \
        "$external_beta_01_record" "$external_beta_02_record" "$external_beta_03_record" \
        "$source_directory/release-manifest.json" \
        "$source_directory/Desk-Setup-Switcher-0.1.0.provenance.sigstore.json" \
        "$predecessor_source_directory/release-manifest.json" \
        "$predecessor_source_directory/Desk-Setup-Switcher-0.0.9.provenance.sigstore.json" \
        "$predecessor_source_directory/Desk-Setup-Switcher-0.0.9.dmg" \
        "$final_dmg_sha" "$predecessor_final_dmg_sha" "$scenario" "$mock_now"
    FIXTURE_SCENARIO="$scenario" "$real_ruby" -rjson -rtime -e '
      candidate_path, publication_path, final_candidate_path, final_publication_path, now_text,
        scenario = ARGV
      now = Time.iso8601(now_text)
      actor = { "id" => 1001, "login" => "GGULBAE", "type" => "User" }
      base = {
        "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
        "administratorBypassEnabled" => false,
        "observer" => actor,
        "redactionReviewed" => true
      }
      controls = [
        ["release-candidate-administrator-bypass-disabled", []],
        [
          "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
          %w[actions:read administration:read attestations:read contents:read metadata:read]
        ]
      ]
      final_paths = [final_candidate_path, final_publication_path]
      current_paths = [candidate_path, publication_path]
      controls.each_with_index do |(control, permissions), index|
        final_observed = case scenario
        when "historical-final-stale"
          now - 10 * 86_400
        when "final-manual-stale-at-collection"
          now - 6 * 86_400 - 90_001
        when "final-manual-after-final-collected"
          now
        else
          now - 7 * 86_400
        end
        token_for = lambda do |observed|
          if index.zero?
            nil
          else
            {
            "type" => "fine-grained-personal-access-token",
            "resourceOwner" => "GGULBAE",
            "repositorySelection" => ["GGULBAE/desk-setup-switcher"],
            "accountPermissions" => [],
            "organizationPermissions" => [],
              "issuedAt" => observed.iso8601,
              "expiresAt" => (observed + 30 * 86_400).iso8601
            }
          end
        end
        final_token = token_for.call(final_observed)
        current_token = token_for.call(now)
        if index == 1 && scenario == "final-token-short-residual"
          final_token["expiresAt"] = (now - 6 * 86_400 + 899).iso8601
        end
        if index == 1 && scenario == "manual-token-extra-repository"
          current_token["repositorySelection"] << "GGULBAE/other-private-repository"
        end
        if index == 1 && scenario == "manual-token-expired"
          current_token["expiresAt"] = (now - 60).iso8601
        end
        if index == 1 && scenario == "manual-token-overlong"
          current_token["expiresAt"] = (now + 30 * 86_400 + 1).iso8601
        end
        final = base.merge(
          "phase" => "final-pre-tag",
          "control" => control,
          "token" => final_token,
          "tokenPermissions" => permissions,
          "observedAt" => final_observed.iso8601,
          "sourceArtifactSHA256" => (index + 1).to_s * 64,
          "subject" => { "tag" => "v0.1.0" }
        )
        current_source_index = scenario == "manual-source-reuse" ? index + 1 : index + 3
        current_observed = case scenario
        when "manual-stale"
          now - 2 * 86_400
        when "pre-manual-before-final-collected"
          now - 7 * 86_400
        when "pre-manual-after-pre-collected"
          now + 1
        else
          now
        end
        current = base.merge(
          "phase" => scenario == "manual-phase-mismatch" ? "final-pre-tag" : "pre-publication",
          "control" => control,
          "token" => current_token,
          "tokenPermissions" => permissions,
          "observedAt" => current_observed.iso8601,
          "sourceArtifactSHA256" => current_source_index.to_s * 64,
          "subject" => {
            "peeledCommit" => "a" * 40,
            "releaseId" => 7001,
            "tag" => "v0.1.0",
            "tagObjectSha" => "8" * 40
          }
        )
        File.binwrite(final_paths.fetch(index), JSON.generate(final) + "\n")
        File.binwrite(current_paths.fetch(index), JSON.generate(current) + "\n")
      end
    ' "$candidate_manual_record" "$publication_manual_record" \
        "$final_candidate_manual_record" "$final_publication_manual_record" \
        "$mock_now" "$scenario"
    candidate_manual_sha="$(shasum -a 256 "$candidate_manual_record" | awk '{print $1}')"
    publication_manual_sha="$(shasum -a 256 "$publication_manual_record" | awk '{print $1}')"
    FIXTURE_SCENARIO="$scenario" "$real_ruby" -rjson -rdigest -rtime -e '
      policy_source, evidence_source, final_source, policy_output, evidence_output,
        final_output, observed_master, candidate_manual_sha, publication_manual_sha,
        final_candidate_manual_sha, final_publication_manual_sha, pre_collected_at = ARGV
      policy = JSON.parse(File.binread(policy_source), create_additions: false)
      evidence = JSON.parse(File.binread(evidence_source), create_additions: false)
      final_evidence = JSON.parse(File.binread(final_source), create_additions: false)
      rewrite = lambda do |value|
        case value
        when Hash
          value.each { |key, child| value[key] = rewrite.call(child) }
        when Array
          value.map! { |child| rewrite.call(child) }
        when String
          return "GGULBAE/desk-setup-switcher" if value == "synthetic-operator/desk-setup-switcher"
          return "GGULBAE" if value.casecmp?("synthetic-operator")
          return "release-reviewer" if value.casecmp?("synthetic-reviewer")
          return observed_master if value == "a" * 40
          return "a" * 40 if value == "9" * 40
          value
        else
          value
        end
      end
      rewrite.call(policy)
      rewrite.call(evidence)
      evidence["schemaVersion"] = "desk-setup-switcher.remote-release-controls-evidence/v3"
      evidence["phase"] = "pre-publication"
      evidence["predecessorPreTagEvidenceSHA256"] = "1" * 64
      evidence.dig("environments", "releaseCandidate", "deployment", "policies").replace(
        [
          { "name" => "v0.0.9", "type" => "tag" },
          { "name" => "v0.1.0", "type" => "tag" }
        ]
      )
      evidence["collectedAt"] = if ENV["FIXTURE_SCENARIO"] == "pre-collected-after-approval"
        (Time.iso8601(pre_collected_at) + 1).iso8601
      else
        pre_collected_at
      end
      rewrite_final = lambda do |value|
        case value
        when Hash
          value.each { |key, child| value[key] = rewrite_final.call(child) }
        when Array
          value.map! { |child| rewrite_final.call(child) }
        when String
          return "GGULBAE/desk-setup-switcher" if value == "synthetic-operator/desk-setup-switcher"
          return "GGULBAE" if value.casecmp?("synthetic-operator")
          return "release-reviewer" if value.casecmp?("synthetic-reviewer")
          value
        else
          value
        end
      end
      rewrite_final.call(final_evidence)
      final_evidence["schemaVersion"] = "desk-setup-switcher.remote-release-controls-evidence/v3"
      final_evidence["phase"] = "final-pre-tag"
      final_evidence["predecessorPreTagEvidenceSHA256"] = "1" * 64
      final_evidence["finalPreTagEvidenceSHA256"] = nil
      final_evidence.dig("environments", "releaseCandidate", "deployment", "policies").replace(
        [
          { "name" => "v0.0.9", "type" => "tag" },
          { "name" => "v0.1.0", "type" => "tag" }
        ]
      )
      pre_collected = Time.iso8601(pre_collected_at)
      final_evidence["collectedAt"] = if ENV["FIXTURE_SCENARIO"] == "historical-final-stale"
        (pre_collected - 9 * 86_400).iso8601
      else
        (pre_collected - 6 * 86_400).iso8601
      end
      final_manual = final_evidence.fetch("manualEvidence").fetch("items")
      final_manual.fetch(0)["sha256"] = final_candidate_manual_sha
      final_manual.fetch(1)["sha256"] = final_publication_manual_sha
      if ENV["FIXTURE_SCENARIO"] == "final-manual-digest-mismatch"
        final_manual.fetch(0)["sha256"] = "0" * 64
      end
      predecessor_ref = {
        "ref" => "refs/tags/v0.0.9",
        "objectType" => "tag",
        "objectSha" => "5" * 40,
        "commitSha" => "9" * 40
      }
      release_ref = {
        "ref" => "refs/tags/v0.1.0",
        "objectType" => "tag",
        "objectSha" => "8" * 40,
        "commitSha" => "a" * 40
      }
      final_evidence["releaseBoundary"] = {
        "vRefs" => { "complete" => true, "items" => [predecessor_ref] },
        "releases" => { "complete" => true, "items" => [] }
      }
      File.binwrite(final_output, JSON.pretty_generate(final_evidence) + "\n")
      evidence["finalPreTagEvidenceSHA256"] = Digest::SHA256.file(final_output).hexdigest
      evidence["releaseBoundary"] = {
        "vRefs" => { "complete" => true, "items" => [predecessor_ref, release_ref] },
        "releases" => {
          "complete" => true,
          "items" => [
            { "id" => 7001, "tag" => "v0.1.0", "draft" => true, "prerelease" => true }
          ]
        }
      }
      manual = evidence.fetch("manualEvidence").fetch("items")
      manual.fetch(0)["sha256"] = candidate_manual_sha
      manual.fetch(1)["sha256"] = publication_manual_sha
      if ENV["FIXTURE_SCENARIO"] == "controls-evidence-invalid"
        evidence.fetch("publicationWorkflow")["state"] = "disabled_manually"
      end
      File.binwrite(policy_output, JSON.pretty_generate(policy) + "\n")
      File.binwrite(evidence_output, JSON.pretty_generate(evidence) + "\n")
    ' \
        "$ROOT_DIR/scripts/release/fixtures/remote-controls/policy-v3.json" \
        "$ROOT_DIR/scripts/release/fixtures/remote-controls/evidence-v2-pre-publication.json" \
        "$ROOT_DIR/scripts/release/fixtures/remote-controls/evidence-v2-final-pre-tag.json" \
        "$remote_controls_policy" "$remote_controls_record" "$final_pre_tag_evidence_record" \
        "$observed_master" "$candidate_manual_sha" "$publication_manual_sha" \
        "$(shasum -a 256 "$final_candidate_manual_record" | awk '{print $1}')" \
        "$(shasum -a 256 "$final_publication_manual_record" | awk '{print $1}')" \
        "$mock_now"
    final_pre_tag_evidence_sha="$(shasum -a 256 "$final_pre_tag_evidence_record" | awk '{print $1}')"
    "$real_ruby" -rjson -rdigest -e '
      lineage_path, set_path, boundary_path, *report_paths = ARGV
      lineage = JSON.parse(File.binread(lineage_path), create_additions: false)
      lineage.fetch("upgradePredecessor")["releaseBoundaryEvidenceSHA256"] =
        Digest::SHA256.file(boundary_path).hexdigest
      File.binwrite(lineage_path, JSON.generate(lineage) + "\n")
      lineage_sha = Digest::SHA256.file(lineage_path).hexdigest
      reports = report_paths.map do |path|
        value = JSON.parse(File.binread(path), create_additions: false)
        value.fetch("subject")["predecessorLineageSHA256"] = lineage_sha
        File.binwrite(path, JSON.generate(value) + "\n")
        value
      end
      report_sha = report_paths.map { |path| Digest::SHA256.file(path).hexdigest }
      beta_set = JSON.parse(File.binread(set_path), create_additions: false)
      beta_set.fetch("subject")["predecessorLineageSHA256"] = lineage_sha
      report_sha.each_with_index do |digest, index|
        beta_set.fetch("reports").fetch(index)["reportSHA256"] = digest
        beta_set.fetch("independence").fetch("bindings").fetch(index)["reportSHA256"] = digest
      end
      File.binwrite(set_path, JSON.generate(beta_set) + "\n")
    ' "$predecessor_lineage_record" "$external_beta_set_record" \
        "$final_pre_tag_evidence_record" "$external_beta_01_record" \
        "$external_beta_02_record" "$external_beta_03_record"
    if [[ "$scenario" == predecessor-manifest-byte-mismatch ]]; then
        printf ' ' >>"$predecessor_source_directory/release-manifest.json"
    fi
    if [[ "$scenario" == beta-set-binding-mismatch ]]; then
        "$real_ruby" -rjson -e '
          path = ARGV.fetch(0)
          value = JSON.parse(File.binread(path), create_additions: false)
          value.fetch("independence").fetch("bindings").fetch(0)["reportSHA256"] = "0" * 64
          File.binwrite(path, JSON.generate(value) + "\n")
        ' "$external_beta_set_record"
    fi
    remote_controls_sha="$(shasum -a 256 "$remote_controls_record" | awk '{print $1}')"
    release_manifest_sha="$(shasum -a 256 "$source_directory/release-manifest.json" | awk '{print $1}')"
    final_dmg_provenance_sha="$(
        shasum -a 256 "$source_directory/Desk-Setup-Switcher-0.1.0.provenance.sigstore.json" \
            | awk '{print $1}'
    )"
    candidate_inventory_sha="$(shasum -a 256 "$candidate_inventory_record" | awk '{print $1}')"
    predecessor_lineage_sha="$(shasum -a 256 "$predecessor_lineage_record" | awk '{print $1}')"
    external_beta_set_sha="$(shasum -a 256 "$external_beta_set_record" | awk '{print $1}')"
    external_beta_01_sha="$(shasum -a 256 "$external_beta_01_record" | awk '{print $1}')"
    external_beta_02_sha="$(shasum -a 256 "$external_beta_02_record" | awk '{print $1}')"
    external_beta_03_sha="$(shasum -a 256 "$external_beta_03_record" | awk '{print $1}')"
    write_approval_record \
        "$approval_record" "$final_dmg_sha" "$scenario" "$observed_master" "$remote_controls_sha" \
        "$mock_now" "$release_manifest_sha" "$final_dmg_provenance_sha" \
        "$candidate_inventory_sha" "$predecessor_lineage_sha" "$external_beta_set_sha" \
        "$external_beta_01_sha" "$external_beta_02_sha" "$external_beta_03_sha"
    if [[ "$scenario" == controls-digest-mismatch ]]; then
        printf ' \n' >>"$remote_controls_record"
    fi
    if [[ "$scenario" == beta-report-byte-mismatch ]]; then
        printf ' ' >>"$external_beta_01_record"
    fi
    if [[ "$scenario" == candidate-inventory-byte-mismatch ]]; then
        printf ' ' >>"$candidate_inventory_record"
    fi
    approval_sha="$(shasum -a 256 "$approval_record" | awk '{print $1}')"
    printf '0\n' >"$state_directory/master-reads"
    printf '0\n' >"$state_directory/tag-reads"
    printf '0\n' >"$state_directory/immutable-reads"
    printf '0\n' >"$state_directory/verified-time-reads"
    printf 'draft\n' >"$state_directory/release-state"
    : >"$command_log"
    : >"$mutation_log"
    case "$scenario" in
        already-published|published-mutable|published-before-approval|published-in-future)
            printf 'published\n' >"$state_directory/release-state"
            publication_attempt=2
            ;;
        preexisting-public-first-attempt)
            printf 'published\n' >"$state_directory/release-state"
            ;;
        rerun-attempt)
            publication_attempt=2
            ;;
    esac
    if [[ "$scenario" == actor-mismatch ]]; then
        effective_scenario=complete
    fi
    if [[ "$scenario" == stale-approval ]]; then
        effective_scenario=complete
        master_commit="$(printf 'e%.0s' {1..40})"
    fi

    environment=(
        "PATH=$mock_bin:/usr/bin:/bin:/usr/sbin:/sbin"
        "LANG=en_US.UTF-8"
        "LC_ALL=en_US.UTF-8"
        "MOCK_REAL_RUBY=$real_ruby"
        "MOCK_GH_RUBY=$temporary_root/mock-gh.rb"
        "MOCK_ROOT_DIR=$publisher_target_root"
        "MOCK_TAG=v0.1.0"
        "MOCK_PREDECESSOR_TAG=v0.0.9"
        "MOCK_TAG_OBJECT=$(printf '8%.0s' {1..40})"
        "MOCK_EXPECTED_COMMIT=$(printf 'a%.0s' {1..40})"
        "MOCK_PREDECESSOR_COMMIT=$(printf '9%.0s' {1..40})"
        "MOCK_PREDECESSOR_TAG_OBJECT=$(printf '5%.0s' {1..40})"
        "MOCK_APPROVAL_COMMIT=$(printf 'd%.0s' {1..40})"
        "MOCK_FINAL_EVIDENCE_COMMIT=$(printf 'f%.0s' {1..40})"
        "MOCK_OBSERVED_MASTER=$observed_master"
        "MOCK_MASTER_COMMIT=$master_commit"
        "MOCK_CANDIDATE_WORKFLOW_BLOB=$(printf 'b%.0s' {1..40})"
        "MOCK_CI_WORKFLOW_BLOB=$(printf 'c%.0s' {1..40})"
        "MOCK_PUBLICATION_WORKFLOW_BLOB=$(printf 'd%.0s' {1..40})"
        "MOCK_LEGACY_WORKFLOW_BLOB=$(printf 'e%.0s' {1..40})"
        "MOCK_NOTES_RELATIVE=docs/releases/v0.1.0.md"
        "MOCK_NOTES_PATH=$notes_path"
        "MOCK_APPROVAL_RELATIVE=docs/evidence/releases/v0.1.0/publication-approval.json"
        "MOCK_APPROVAL_SOURCE=$approval_record"
        "MOCK_CONTROLS_RELATIVE=docs/evidence/releases/v0.1.0/remote-controls-pre-publication.json"
        "MOCK_CONTROLS_SOURCE=$remote_controls_record"
        "MOCK_CANDIDATE_INVENTORY_RELATIVE=docs/evidence/releases/v0.1.0/candidate-inventory.json"
        "MOCK_CANDIDATE_INVENTORY_SOURCE=$candidate_inventory_record"
        "MOCK_PREDECESSOR_LINEAGE_RELATIVE=docs/evidence/releases/v0.1.0/predecessor-lineage.json"
        "MOCK_PREDECESSOR_LINEAGE_SOURCE=$predecessor_lineage_record"
        "MOCK_EXTERNAL_BETA_SET_RELATIVE=docs/evidence/releases/v0.1.0/external-beta-set.json"
        "MOCK_EXTERNAL_BETA_SET_SOURCE=$external_beta_set_record"
        "MOCK_EXTERNAL_BETA_01_RELATIVE=docs/evidence/releases/v0.1.0/external-beta-01.json"
        "MOCK_EXTERNAL_BETA_01_SOURCE=$external_beta_01_record"
        "MOCK_EXTERNAL_BETA_02_RELATIVE=docs/evidence/releases/v0.1.0/external-beta-02.json"
        "MOCK_EXTERNAL_BETA_02_SOURCE=$external_beta_02_record"
        "MOCK_EXTERNAL_BETA_03_RELATIVE=docs/evidence/releases/v0.1.0/external-beta-03.json"
        "MOCK_EXTERNAL_BETA_03_SOURCE=$external_beta_03_record"
        "MOCK_POLICY_RELATIVE=scripts/release/remote-controls-policy.json"
        "MOCK_POLICY_SOURCE=$remote_controls_policy"
        "MOCK_CANDIDATE_MANUAL_RELATIVE=docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json"
        "MOCK_PUBLICATION_MANUAL_RELATIVE=docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json"
        "MOCK_FINAL_EVIDENCE_RELATIVE=docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json"
        "MOCK_CANDIDATE_MANUAL_SOURCE=$candidate_manual_record"
        "MOCK_PUBLICATION_MANUAL_SOURCE=$publication_manual_record"
        "MOCK_FINAL_CANDIDATE_MANUAL_SOURCE=$final_candidate_manual_record"
        "MOCK_FINAL_PUBLICATION_MANUAL_SOURCE=$final_publication_manual_record"
        "MOCK_FINAL_EVIDENCE_SOURCE=$final_pre_tag_evidence_record"
        "MOCK_FINAL_EVIDENCE_SHA256=$final_pre_tag_evidence_sha"
        "MOCK_EXPECTED_ASSETS=$expected_assets"
        "MOCK_REMOTE_ASSETS=$remote_directory"
        "MOCK_STATE_DIR=$state_directory"
        "MOCK_COMMAND_LOG=$command_log"
        "MOCK_MUTATION_LOG=$mutation_log"
        "MOCK_PATCH_HANG_MARKER=$patch_hang_marker"
        "MOCK_SCENARIO=$effective_scenario"
        "MOCK_NOW=$mock_now"
        "MOCK_WRITE_TOKEN_SHA256=$runtime_write_token_sha256"
        "MOCK_ADMIN_READ_TOKEN_SHA256=$runtime_admin_read_token_sha256"
        "GH_TOKEN=$runtime_write_token"
        "RELEASE_ADMIN_READ_TOKEN=$runtime_admin_read_token"
        "GH_HOST=evil.example.invalid"
        "GH_DEBUG=api"
        "DEBUG=1"
        "GH_ENTERPRISE_TOKEN=$runtime_enterprise_token"
        "GITHUB_ENTERPRISE_TOKEN=$runtime_github_enterprise_token"
        "GH_CONFIG_DIR=$runner_temp/hostile-gh-config"
        "DESK_SETUP_RELEASE_MUTATIONS=1"
        "GITHUB_ACTIONS=true"
        "GITHUB_EVENT_NAME=workflow_dispatch"
        "GITHUB_REF_TYPE=tag"
        "GITHUB_REF=refs/tags/v0.1.0"
        "GITHUB_REF_NAME=v0.1.0"
        "GITHUB_REPOSITORY=GGULBAE/desk-setup-switcher"
        "GITHUB_RUN_ID=8101"
        "GITHUB_RUN_ATTEMPT=$publication_attempt"
        "GITHUB_ACTOR=GGULBAE"
        "GITHUB_ACTOR_ID=1001"
        "GITHUB_TRIGGERING_ACTOR=GGULBAE"
        "RUNNER_ENVIRONMENT=github-hosted"
        "RUNNER_TEMP=$runner_temp"
        "RELEASE_OPERATION=publish-release"
        "RELEASE_TAG=v0.1.0"
        "EXPECTED_COMMIT=$(printf 'a%.0s' {1..40})"
        "RELEASE_ID=7001"
        "RELEASE_CANDIDATE_RUN_ID=8001"
        "RELEASE_CANDIDATE_RUN_ATTEMPT=1"
        "RELEASE_CANDIDATE_ARTIFACT_ID=9001"
        "RELEASE_CANDIDATE_ARTIFACT_SHA256=$(printf 'b%.0s' {1..64})"
        "RELEASE_FINAL_DMG_SHA256=$final_dmg_sha"
        "RELEASE_PREDECESSOR_COMMIT=$(printf '9%.0s' {1..40})"
        "RELEASE_PREDECESSOR_RUN_ID=7999"
        "RELEASE_PREDECESSOR_ARTIFACT_ID=8999"
        "RELEASE_PREDECESSOR_ARTIFACT_SHA256=$(printf '7%.0s' {1..64})"
        "RELEASE_PREDECESSOR_FINAL_DMG_SHA256=$predecessor_final_dmg_sha"
        "RELEASE_PREDECESSOR_SOURCE_DIR=$predecessor_source_directory"
        "RELEASE_APPROVAL_RECORD_COMMIT=$(printf 'd%.0s' {1..40})"
        "RELEASE_APPROVAL_RECORD_SHA256=$approval_sha"
        "RELEASE_APPROVAL_RECORD_PATH=docs/evidence/releases/v0.1.0/publication-approval.json"
        "RELEASE_APPROVER_LOGIN=release-reviewer"
        "RELEASE_PUBLISHER_LOGIN=GGULBAE"
        "RELEASE_CONFIRMATION=publish approved v0.1.0 release 7001"
        "RELEASE_PROTECTED_ENVIRONMENT=release-publication"
        "RELEASE_NOTES_PATH=docs/releases/v0.1.0.md"
        "RELEASE_SOURCE_DIR=$source_directory"
        "RELEASE_DOWNLOAD_DIR=$download_directory"
    )
    if [[ "$scenario" == predecessor-final-dmg-pin-mismatch ]]; then
        environment+=("RELEASE_PREDECESSOR_FINAL_DMG_SHA256=$(printf '0%.0s' {1..64})")
    fi
    if [[ "$scenario" == actor-mismatch ]]; then
        environment+=("GITHUB_TRIGGERING_ACTOR=other-actor")
    fi
    if [[ "$scenario" == actor-numeric-mismatch ]]; then
        environment+=("GITHUB_ACTOR_ID=9999")
    fi
    if [[ "$scenario" == policy-reviewer-input-mismatch ]]; then
        environment+=("RELEASE_APPROVER_LOGIN=other-reviewer")
    fi
    if [[ "$scenario" == same-token ]]; then
        environment+=("RELEASE_ADMIN_READ_TOKEN=$runtime_write_token")
    fi

    set +e
    if [[ "$scenario" == patch-signal-hang ]]; then
        env -i "${environment[@]}" "$publisher_target" \
            >"$stdout_path" 2>"$stderr_path" &
        publisher_pid=$!
        marker_ready=false
        for _attempt in {1..400}; do
            if [[ -s "$patch_hang_marker" ]]; then
                marker_ready=true
                break
            fi
            kill -0 "$publisher_pid" >/dev/null 2>&1 || break
            sleep 0.05
        done
        if [[ "$marker_ready" != true ]]; then
            kill -TERM "$publisher_pid" >/dev/null 2>&1 || true
            wait "$publisher_pid" >/dev/null 2>&1 || true
            set -e
            printf 'Scenario %s never reached the tracked PATCH child.\n' "$scenario" >&2
            sed -n '1,80p' "$stderr_path" >&2
            return 1
        fi
        IFS=$'\t' read -r patch_child_pid patch_launcher_pid <"$patch_hang_marker"
        patch_launcher_parent_pid="$(ps -o ppid= -p "$patch_launcher_pid" | tr -d '[:space:]')"
        kill -TERM "$publisher_pid"
        wait "$publisher_pid"
        status=$?
        sleep 0.2
        if kill -0 "$patch_child_pid" >/dev/null 2>&1; then
            set -e
            printf 'Scenario %s left the tracked PATCH child alive.\n' "$scenario" >&2
            kill -KILL "$patch_child_pid" >/dev/null 2>&1 || true
            return 1
        fi
        if kill -0 "$patch_launcher_pid" >/dev/null 2>&1; then
            set -e
            printf 'Scenario %s left the tracked PATCH launcher alive.\n' "$scenario" >&2
            kill -KILL "$patch_launcher_pid" >/dev/null 2>&1 || true
            return 1
        fi
        [[ "$status" == 143 && "$patch_launcher_parent_pid" == "$publisher_pid" ]] || {
            set -e
            printf 'Scenario %s returned %s with launcher parent %s; expected 143/%s.\n' \
                "$scenario" "$status" "$patch_launcher_parent_pid" "$publisher_pid" >&2
            return 1
        }
        if find "$runner_temp" -maxdepth 1 -name 'desk-setup-release-publication.*' -print -quit \
            | grep -q .; then
            set -e
            printf 'Scenario %s leaked a publication temporary directory.\n' "$scenario" >&2
            return 1
        fi
        pass
    else
        env -i "${environment[@]}" "$publisher_target" \
            >"$stdout_path" 2>"$stderr_path"
        status=$?
    fi
    set -e

    patch_count="$(wc -l <"$mutation_log" | tr -d '[:space:]')"
    [[ "$patch_count" == "$expected_patch_count" ]] || {
        printf 'Scenario %s made %s PATCH attempts; expected %s.\n' "$scenario" "$patch_count" "$expected_patch_count" >&2
        sed -n '1,80p' "$stderr_path" >&2
        if [[ -s "$state_directory/remote-policy.stderr" ]]; then
            sed -n '1,40p' "$state_directory/remote-policy.stderr" >&2
            sed -n '1,40p' "$state_directory/remote-policy.args" >&2
        fi
        return 1
    }
    pass

    if [[ "$expected_result" == success ]]; then
        [[ "$status" == 0 ]] || {
            printf 'Scenario %s unexpectedly failed:\n' "$scenario" >&2
            sed -n '1,80p' "$stderr_path" >&2
            return 1
        }
        [[ -d "$download_directory" && ! -L "$download_directory" ]] || return 1
        for name in "${asset_names[@]}"; do
            cmp -s "$source_directory/$name" "$download_directory/$name" || return 1
        done
        pass
        grep -q 'Published exact immutable public beta Release ID 7001' "$stdout_path" || return 1
        pass
        ! grep -q '^SAFE_PRE_PATCH_FAILURE$\|^INCIDENT_ONLY_FAILURE$' "$stderr_path" || {
            printf 'Scenario %s emitted a failure classification despite succeeding.\n' "$scenario" >&2
            return 1
        }
        pass
    else
        [[ "$status" != 0 ]] || {
            printf 'Scenario %s unexpectedly succeeded.\n' "$scenario" >&2
            return 1
        }
        [[ ! -e "$download_directory" && ! -L "$download_directory" ]] || return 1
        pass
        output_bytes="$(<"$stdout_path")$(<"$stderr_path")"
        if [[ "$output_bytes" == *SENSITIVE_REMOTE_MARKER* \
            || "$output_bytes" == *"$runtime_write_token"* \
            || "$output_bytes" == *"$runtime_admin_read_token"* ]]; then
            printf 'Scenario %s leaked a remote response or credential.\n' "$scenario" >&2
            return 1
        fi
        unset output_bytes
        pass
    fi

    if grep -E -q 'release (create|edit|delete|upload)|--clobber|:refs/tags/' "$command_log"; then
        printf 'Scenario %s invoked a forbidden mutation.\n' "$scenario" >&2
        return 1
    fi
    pass

    incident_only=false
    case "$scenario" in
        already-published|rerun-attempt|preexisting-public-first-attempt|published-mutable|published-before-approval|published-in-future)
            incident_only=true
            ;;
    esac
    if [[ "$incident_only" == true ]]; then
        grep -q '^INCIDENT_ONLY_FAILURE$' "$stderr_path" || {
            printf 'Scenario %s lacks the incident-only marker.\n' "$scenario" >&2
            return 1
        }
        ! grep -q '^SAFE_PRE_PATCH_FAILURE$\|^PATCH_ATTEMPT_BEGIN$' "$stderr_path" || return 1
    elif [[ "$expected_patch_count" == 0 && "$scenario" != patch-signal-hang ]]; then
        grep -q '^SAFE_PRE_PATCH_FAILURE$' "$stderr_path" || {
            printf 'Scenario %s lacks the normal pre-PATCH failure marker.\n' "$scenario" >&2
            return 1
        }
        ! grep -q '^PATCH_ATTEMPT_BEGIN$' "$stderr_path" || return 1
    else
        grep -q '^PATCH_ATTEMPT_BEGIN$' "$stderr_path" || {
            printf 'Scenario %s lacks the PATCH-attempt marker.\n' "$scenario" >&2
            return 1
        }
        ! grep -q '^SAFE_PRE_PATCH_FAILURE$' "$stderr_path" || return 1
        if [[ "$expected_result" == failure && "$scenario" != patch-signal-hang ]]; then
            grep -q '^INCIDENT_ONLY_FAILURE$' "$stderr_path" || {
                printf 'Scenario %s lacks the post-boundary incident marker.\n' "$scenario" >&2
                return 1
            }
        fi
    fi
    pass
    unset incident_only

    case "$scenario" in
        candidate-inventory-byte-mismatch|candidate-inventory-schema-invalid|predecessor-build-reuse|\
        predecessor-manifest-byte-mismatch|predecessor-provenance-binding-mismatch|\
        beta-report-byte-mismatch|beta-wrong-candidate|beta-duplicate-code|beta-missing-sonoma|\
        beta-lifecycle-failed|beta-quarantine-invalid|beta-installation-failed|\
        beta-predecessor-installation-failed|beta-independent-false|\
        beta-provenance-mismatch|beta-set-binding-mismatch)
            grep -q 'The external-beta or predecessor-lineage evidence is invalid.' "$stderr_path" || {
                printf 'Scenario %s did not fail at the external-beta gate.\n' "$scenario" >&2
                return 1
            }
            pass
            ;;
    esac

    if [[ "$expected_patch_count" -gt 0 ]]; then
        "$real_ruby" -rjson -e '
          calls = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
          patch_index = calls.index { |call| call.each_cons(2).any? { |a, b| a == "--method" && b == "PATCH" } }
          raise unless patch_index && patch_index >= 3
          endpoints = calls.map(&:last)
          expected = [
            "/repos/GGULBAE/desk-setup-switcher/releases?per_page=100",
            "/repos/GGULBAE/desk-setup-switcher/releases/7001/assets?per_page=100",
            "/repos/GGULBAE/desk-setup-switcher/releases/7001",
            "/repos/GGULBAE/desk-setup-switcher/releases/7001"
          ]
          raise unless endpoints[(patch_index - 3)..patch_index] == expected
        ' "$command_log" || {
            printf 'Scenario %s did not make list -> assets -> exact-ID GET the final network reads before PATCH.\n' \
                "$scenario" >&2
            return 1
        }
        pass
    fi
}

run_scenario complete success 1
run_scenario historical-final-stale success 1
run_scenario already-published failure 0
run_scenario rerun-attempt failure 0
run_scenario ambiguous-success success 1
run_scenario invalid-patch-response success 1

run_scenario immutable-disabled failure 0
run_scenario immutable-extra-key failure 0
run_scenario admin-api-failure failure 0
run_scenario api-failure failure 0
run_scenario title-mismatch failure 0
run_scenario notes-mismatch failure 0
run_scenario release-id-mismatch failure 0
run_scenario target-empty failure 0
run_scenario release-url-mismatch failure 0
run_scenario upload-url-mismatch failure 0
run_scenario release-updated-after-approval failure 0
run_scenario final-exact-metadata-drift failure 0
run_scenario approval-near-expiry-before-patch failure 0
run_scenario approval-near-expiry-after-controls failure 0
run_scenario other-release failure 0
run_scenario extra-asset failure 0
run_scenario asset-mismatch failure 0
run_scenario approval-mismatch failure 0
run_scenario approval-before-draft failure 0
run_scenario actor-mismatch failure 0
run_scenario actor-numeric-mismatch failure 0
run_scenario actor-api-id-mismatch failure 0
run_scenario reviewer-api-id-mismatch failure 0
run_scenario admin-token-owner-mismatch failure 0
run_scenario same-token failure 0
run_scenario policy-reviewer-input-mismatch failure 0
run_scenario approval-mode-mismatch failure 0
run_scenario stale-approval failure 0
run_scenario approval-merge-commit failure 0
run_scenario approval-extra-path failure 0
run_scenario release-critical-drift failure 0
run_scenario evidence-history-gate-rejected failure 0
run_scenario controls-evidence-invalid failure 0
run_scenario controls-digest-mismatch failure 0
run_scenario candidate-inventory-byte-mismatch failure 0
run_scenario candidate-inventory-schema-invalid failure 0
run_scenario predecessor-source-extra failure 0
run_scenario predecessor-final-dmg-pin-mismatch failure 0
run_scenario predecessor-manifest-byte-mismatch failure 0
run_scenario predecessor-provenance-binding-mismatch failure 0
run_scenario beta-report-byte-mismatch failure 0
run_scenario beta-wrong-candidate failure 0
run_scenario beta-duplicate-code failure 0
run_scenario beta-missing-sonoma failure 0
run_scenario beta-lifecycle-failed failure 0
run_scenario beta-quarantine-invalid failure 0
run_scenario beta-installation-failed failure 0
run_scenario beta-predecessor-installation-failed failure 0
run_scenario beta-independent-false failure 0
run_scenario beta-provenance-mismatch failure 0
run_scenario predecessor-build-reuse failure 0
run_scenario beta-set-binding-mismatch failure 0
run_scenario final-evidence-two-introductions failure 0
run_scenario final-evidence-merge-introduction failure 0
run_scenario final-evidence-second-parent failure 0
run_scenario final-evidence-extra-path failure 0
run_scenario final-evidence-blob-mismatch failure 0
run_scenario final-evidence-tag-digest-mismatch failure 0
run_scenario final-manual-digest-mismatch failure 0
run_scenario final-manual-stale-at-collection failure 0
run_scenario final-token-short-residual failure 0
run_scenario final-manual-after-final-collected failure 0
run_scenario pre-manual-before-final-collected failure 0
run_scenario pre-manual-after-pre-collected failure 0
run_scenario pre-collected-after-approval failure 0
run_scenario manual-source-reuse failure 0
run_scenario manual-stale failure 0
run_scenario manual-phase-mismatch failure 0
run_scenario manual-token-extra-repository failure 0
run_scenario manual-token-expired failure 0
run_scenario manual-token-overlong failure 0
run_scenario approval-ci-failed failure 0
run_scenario approval-ci-ambiguous failure 0
run_scenario approval-ci-job-failed failure 0
run_scenario approval-public-ci-job-failed failure 0
run_scenario approval-ci-job-missing failure 0
run_scenario approval-ci-job-duplicate-id failure 0
run_scenario approval-ci-job-float-count failure 0
run_scenario draft-null failure 0
run_scenario immutable-null failure 0
run_scenario preexisting-public-first-attempt failure 0
run_scenario published-before-approval failure 0
run_scenario published-in-future failure 0
run_scenario master-drift failure 0
run_scenario tag-drift failure 0
run_scenario predecessor-tag-drift failure 0
run_scenario predecessor-tag-delete failure 0
run_scenario master-late-drift failure 0
run_scenario tag-late-drift failure 0
run_scenario immutable-late-drift failure 0
run_scenario patch-signal-hang failure 0
run_scenario patch-failure failure 1
run_scenario predecessor-tag-post-patch-drift failure 1
run_scenario predecessor-tag-post-patch-delete failure 1
run_scenario post-asset-drift failure 1
run_scenario post-other-release-drift failure 1
run_scenario target-drift failure 1
run_scenario post-not-prerelease failure 1
run_scenario published-mutable failure 0

printf 'Approved Release publication mock tests passed (%d assertions).\n' "$assertions"
