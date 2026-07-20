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

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-draft-release-tests.XXXXXX")"
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
    printf 'A GitHub credential reached dirname.\n' >&2
    exit 76
fi
printf 'dirname\n' >>"$MOCK_SECRET_PROBE"
exec /usr/bin/dirname "$@"
MOCK_DIRNAME

cat >"$mock_bin/ruby" <<'MOCK_RUBY'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'A GitHub credential reached ruby.\n' >&2
    exit 77
fi
printf 'ruby\n' >>"$MOCK_SECRET_PROBE"
exec "$MOCK_REAL_RUBY" "$@"
MOCK_RUBY

cat >"$mock_bin/cp" <<'MOCK_CP'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'A GitHub credential reached cp.\n' >&2
    exit 78
fi
printf 'cp\n' >>"$MOCK_SECRET_PROBE"
exec /bin/cp "$@"
MOCK_CP

cat >"$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${GH_TOKEN+x}" || -n "${GITHUB_TOKEN+x}" || -n "${github_token+x}" ]]; then
    printf 'A GitHub credential reached git.\n' >&2
    exit 79
fi
printf 'git\n' >>"$MOCK_SECRET_PROBE"

case "${1:-}" in
    rev-parse)
        case "${2:-}" in
            --show-toplevel) printf '%s\n' "$MOCK_ROOT_DIR" ;;
            HEAD|"refs/tags/$MOCK_TAG^{commit}") printf '%s\n' "$MOCK_EXPECTED_COMMIT" ;;
            "refs/tags/$MOCK_TAG")
                if [[ "$MOCK_SCENARIO" == local-lightweight-tag ]]; then
                    printf '%s\n' "$MOCK_EXPECTED_COMMIT"
                else
                    printf '%s\n' "$MOCK_TAG_OBJECT"
                fi ;;
            "refs/remotes/origin/master^{commit}") printf '%s\n' "$MOCK_MASTER_COMMIT" ;;
            "$MOCK_EXPECTED_COMMIT:.github/workflows"|"$MOCK_MASTER_COMMIT:.github/workflows")
                printf '%040d\n' 31 ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release"|"$MOCK_MASTER_COMMIT:scripts/release")
                if [[ "$MOCK_SCENARIO" == final-evidence-critical-tree-drift \
                    && "$2" == "$MOCK_MASTER_COMMIT:scripts/release" ]]; then
                    printf '%040d\n' 39
                else
                    printf '%040d\n' 32
                fi ;;
            "$MOCK_EXPECTED_COMMIT:.github/workflows/release.yml") printf '%s\n' "$MOCK_CANDIDATE_WORKFLOW_BLOB" ;;
            "$MOCK_EXPECTED_COMMIT:.github/workflows/ci.yml") printf '%s\n' "$MOCK_CI_WORKFLOW_BLOB" ;;
            "$MOCK_EXPECTED_COMMIT:.github/workflows/publish-release.yml") printf '%s\n' "$MOCK_PUBLICATION_WORKFLOW_BLOB" ;;
            *) exit 91 ;;
        esac
        ;;
    remote)
        [[ "$#" == 3 && "$2" == get-url && "$3" == origin ]] || exit 92
        printf 'https://github.com/GGULBAE/desk-setup-switcher.git\n'
        ;;
    check-ref-format)
        [[ "$#" == 3 && "$2" == --allow-onelevel && "$3" == "$MOCK_TAG" ]] || exit 93
        ;;
    show-ref)
        [[ "$#" == 4 && "$2" == --verify && "$3" == --quiet ]] || exit 94
        [[ "$4" == "refs/tags/$MOCK_TAG" || "$4" == refs/remotes/origin/master ]] || exit 94
        ;;
    ls-files)
        [[ "$#" == 4 && "$2" == --error-unmatch && "$3" == -- && "$4" == "$MOCK_RELEASE_NOTES_RELATIVE" ]] || exit 95
        printf '%s\n' "$MOCK_RELEASE_NOTES_RELATIVE"
        ;;
    status)
        [[ "$#" == 3 && "$2" == --porcelain=v1 && "$3" == --untracked-files=all ]] || exit 96
        ;;
    cat-file)
        if [[ "$#" == 3 && "$2" == -t ]]; then
            if [[ "$MOCK_SCENARIO" == local-lightweight-tag && "$3" == "$MOCK_EXPECTED_COMMIT" ]]; then
                printf 'commit\n'
            elif [[ "$3" == "$MOCK_TAG_OBJECT" ]]; then
                printf 'tag\n'
            else
                exit 96
            fi
        elif [[ "$#" == 3 && "$2" == -p && "$3" == "$MOCK_TAG_OBJECT" ]]; then
            tag_digest="$MOCK_FINAL_EVIDENCE_DIGEST"
            if [[ "$MOCK_SCENARIO" == final-evidence-tag-digest-mismatch ]]; then
                tag_digest="$(printf '0%.0s' {1..64})"
            fi
            printf 'object %s\ntype commit\ntag %s\ntagger Synthetic <synthetic@example.invalid> 0 +0000\n\nremote-controls-final-pre-tag-sha256: %s\n' \
                "$MOCK_EXPECTED_COMMIT" "$MOCK_TAG" "$tag_digest"
        else
            exit 96
        fi
        ;;
    merge-base)
        [[ "$#" == 4 && "$2" == --is-ancestor && "$3" == "$MOCK_EXPECTED_COMMIT" \
            && "$4" == "$MOCK_MASTER_COMMIT" ]] || exit 108
        ;;
    log)
        [[ "$#" == 7 && "$2" == --full-history && "$3" == --format=%H && "$4" == --reverse \
            && "$5" == "$MOCK_EXPECTED_COMMIT..$MOCK_MASTER_COMMIT" && "$6" == -- \
            && "$7" == "$MOCK_FINAL_EVIDENCE_PATH" ]] || exit 109
        printf '%s\n' "$MOCK_FINAL_EVIDENCE_COMMIT"
        if [[ "$MOCK_SCENARIO" == final-evidence-two-introductions ]]; then
            printf '%040d\n' 17
        fi
        ;;
    rev-list)
        if [[ "$#" == 3 && "$2" == --first-parent && "$3" == "$MOCK_MASTER_COMMIT" ]]; then
            printf '%s\n' "$MOCK_MASTER_COMMIT"
            if [[ "$MOCK_SCENARIO" != final-evidence-second-parent ]]; then
                printf '%s\n' "$MOCK_FINAL_EVIDENCE_COMMIT"
            fi
            printf '%s\n' "$MOCK_EXPECTED_COMMIT"
            exit 0
        fi
        [[ "$#" == 5 && "$2" == --parents && "$3" == -n && "$4" == 1 \
            && "$5" == "$MOCK_FINAL_EVIDENCE_COMMIT" ]] || exit 110
        printf '%s %s' "$MOCK_FINAL_EVIDENCE_COMMIT" "$MOCK_EXPECTED_COMMIT"
        if [[ "$MOCK_SCENARIO" == final-evidence-merge-introduction ]]; then
            printf ' %040d' 18
        fi
        printf '\n'
        ;;
    diff-tree)
        [[ "$#" == 6 && "$2" == --no-commit-id && "$3" == --name-status && "$4" == -r \
            && "$5" == "$MOCK_EXPECTED_COMMIT" && "$6" == "$MOCK_FINAL_EVIDENCE_COMMIT" ]] || exit 111
        printf 'A\t%s\n' "$MOCK_FINAL_EVIDENCE_PATH"
        if [[ "$MOCK_SCENARIO" == final-evidence-extra-path ]]; then
            printf 'M\tdocs/DISTRIBUTION.md\n'
        fi
        ;;
    ls-tree)
        [[ "$#" == 4 && "$3" == -- ]] || exit 112
        case "$4" in
            "$MOCK_FINAL_EVIDENCE_PATH")
                [[ "$2" == "$MOCK_FINAL_EVIDENCE_COMMIT" || "$2" == "$MOCK_MASTER_COMMIT" ]] || exit 112
                blob_number=19
                if [[ "$MOCK_SCENARIO" == final-evidence-blob-drift && "$2" == "$MOCK_MASTER_COMMIT" ]]; then
                    blob_number=20
                fi
                printf '100644 blob %040d\t%s\n' "$blob_number" "$MOCK_FINAL_EVIDENCE_PATH" ;;
            "$MOCK_CANDIDATE_MANUAL_PATH")
                [[ "$2" == "$MOCK_EXPECTED_COMMIT" ]] || exit 112
                printf '100644 blob %040d\t%s\n' 21 "$MOCK_CANDIDATE_MANUAL_PATH" ;;
            "$MOCK_PUBLICATION_MANUAL_PATH")
                [[ "$2" == "$MOCK_EXPECTED_COMMIT" ]] || exit 112
                printf '100644 blob %040d\t%s\n' 22 "$MOCK_PUBLICATION_MANUAL_PATH" ;;
            *) exit 112 ;;
        esac
        ;;
    show)
        [[ "$#" == 2 ]] || exit 113
        case "$2" in
            "$MOCK_FINAL_EVIDENCE_COMMIT:$MOCK_FINAL_EVIDENCE_PATH")
                if [[ "$MOCK_SCENARIO" == final-evidence-invalid ]]; then
                    printf '{}\n'
                else
                    exec /bin/cat "$MOCK_FINAL_EVIDENCE_SOURCE"
                fi ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release/remote_controls_policy.rb")
                exec /bin/cat "$MOCK_POLICY_VALIDATOR_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release/release_policy.rb")
                exec /bin/cat "$MOCK_RELEASE_POLICY_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release/collect_remote_controls_evidence.rb")
                exec /bin/cat "$MOCK_COLLECTOR_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:scripts/release/remote-controls-policy.json")
                exec /bin/cat "$MOCK_POLICY_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:$MOCK_CANDIDATE_MANUAL_PATH")
                exec /bin/cat "$MOCK_CANDIDATE_MANUAL_SOURCE" ;;
            "$MOCK_EXPECTED_COMMIT:$MOCK_PUBLICATION_MANUAL_PATH")
                exec /bin/cat "$MOCK_PUBLICATION_MANUAL_SOURCE" ;;
            *) exit 113 ;;
        esac
        ;;
    ls-remote)
        [[ "$#" == 6 && "$2" == --exit-code && "$3" == --tags && "$4" == origin \
            && "$5" == "refs/tags/$MOCK_TAG" && "$6" == "refs/tags/$MOCK_TAG^{}" ]] || exit 97
        if [[ "$MOCK_SCENARIO" == remote-tag-drift ]]; then
            printf '%s\trefs/tags/%s\n' "$MOCK_TAG_OBJECT" "$MOCK_TAG"
            printf '%040d\trefs/tags/%s^{}\n' 9 "$MOCK_TAG"
        elif [[ "$MOCK_SCENARIO" == remote-tag-object-drift ]]; then
            printf '%040d\trefs/tags/%s\n' 8 "$MOCK_TAG"
            printf '%s\trefs/tags/%s^{}\n' "$MOCK_EXPECTED_COMMIT" "$MOCK_TAG"
        elif [[ "$MOCK_SCENARIO" == remote-peeled-missing ]]; then
            printf '%s\trefs/tags/%s\n' "$MOCK_TAG_OBJECT" "$MOCK_TAG"
        else
            printf '%s\trefs/tags/%s\n' "$MOCK_TAG_OBJECT" "$MOCK_TAG"
            printf '%s\trefs/tags/%s^{}\n' "$MOCK_EXPECTED_COMMIT" "$MOCK_TAG"
        fi
        ;;
    *) exit 98 ;;
esac
MOCK_GIT

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

received_token="${GH_TOKEN:-}"
unset GH_TOKEN
received_token_sha256="$(printf '%s' "$received_token" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
unset received_token
[[ "$received_token_sha256" == "$MOCK_EXPECTED_GH_TOKEN_SHA256" \
   && -z "${GITHUB_TOKEN+x}" \
   && -z "${github_token+x}" ]] || {
    printf 'The mock gh credential boundary is invalid.\n' >&2
    exit 80
}

printf '%q ' "$@" >>"$MOCK_COMMAND_LOG"
printf '\n' >>"$MOCK_COMMAND_LOG"

release_exists() {
    [[ "$(tr -d '\n' <"$MOCK_STATE_DIR/exists")" == 1 ]]
}

case "${1:-} ${2:-}" in
    "api --hostname")
        [[ "$#" == 12 && "$3" == github.com && "$4" == --method && "$5" == GET \
            && "$6" == --paginate && "$7" == --slurp \
            && "$8" == -H && "$9" == "Accept: application/vnd.github+json" \
            && "${10}" == -H && "${11}" == "X-GitHub-Api-Version: 2022-11-28" \
            && "${12}" == "/repos/GGULBAE/desk-setup-switcher/releases?per_page=100" ]] || exit 81
        if [[ "$MOCK_SCENARIO" == api-failure ]]; then
            printf '{"private_remote_response":"SENSITIVE_REMOTE_MARKER"}\n'
            printf 'SENSITIVE_REMOTE_MARKER\n' >&2
            exit 82
        fi
        "$MOCK_REAL_RUBY" -rjson -e '
          state, scenario, notes_path, title, tag, remote = ARGV
          unless File.read(File.join(state, "exists")).strip == "1"
            puts JSON.generate([[]])
            exit 0
          end
          notes = File.binread(notes_path).force_encoding(Encoding::UTF_8)
          names = File.readlines(File.join(state, "asset-names"), chomp: true)
          draft = scenario == "published" ? false : true
          prerelease = scenario == "not-prerelease" ? false : true
          published_at = scenario == "published" ? "2026-07-18T00:00:00Z" : nil
          release_title = scenario == "title-mismatch" ? "Wrong title" : title
          body = scenario == "notes-mismatch" ? "Wrong notes\n" : notes
          assets = names.each_with_index.map do |name, index|
            path = File.join(remote, name)
            size = File.file?(path) ? File.size(path) : 1
            {
              "id" => 10_000 + index,
              "name" => name,
              "state" => "uploaded",
              "size" => size,
              "updated_at" => "2026-07-18T00:00:%02dZ" % index
            }
          end
          release = {
            "id" => 7001,
            "tag_name" => tag,
            "name" => release_title,
            "body" => body,
            "draft" => draft,
            "prerelease" => prerelease,
            "published_at" => published_at,
            "assets" => assets
          }
          puts JSON.generate([[release]])
        ' "$MOCK_STATE_DIR" "$MOCK_SCENARIO" "$MOCK_RELEASE_NOTES_PATH" \
            "$MOCK_TITLE" "$MOCK_TAG" "$MOCK_REMOTE_ASSETS"
        ;;
    "release create")
        [[ "$3" == "$MOCK_TAG" ]] || exit 83
        shift 3
        repo=false
        draft=false
        prerelease=false
        verify_tag=false
        notes=false
        title=false
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --repo)
                    [[ "${2:-}" == github.com/GGULBAE/desk-setup-switcher ]] || exit 84
                    repo=true
                    shift 2
                    ;;
                --draft) draft=true; shift ;;
                --prerelease) prerelease=true; shift ;;
                --verify-tag) verify_tag=true; shift ;;
                --notes-file)
                    [[ -f "${2:-}" && ! -L "${2:-}" ]] || exit 85
                    cmp -s "$2" "$MOCK_RELEASE_NOTES_PATH" || exit 86
                    notes=true
                    shift 2
                    ;;
                --title)
                    [[ "${2:-}" == "$MOCK_TITLE" ]] || exit 87
                    title=true
                    shift 2
                    ;;
                *) exit 88 ;;
            esac
        done
        [[ "$repo" == true && "$draft" == true && "$prerelease" == true \
            && "$verify_tag" == true && "$notes" == true && "$title" == true ]] || exit 89
        ! release_exists || exit 90
        printf 'create\n' >>"$MOCK_MUTATION_LOG"
        printf '1\n' >"$MOCK_STATE_DIR/exists"
        : >"$MOCK_STATE_DIR/asset-names"
        ;;
    "release upload")
        [[ "$3" == "$MOCK_TAG" ]] || exit 91
        shift 3
        paths=()
        repo=false
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --repo)
                    [[ "${2:-}" == github.com/GGULBAE/desk-setup-switcher ]] || exit 92
                    repo=true
                    shift 2
                    ;;
                --clobber) exit 93 ;;
                --*) exit 94 ;;
                *) paths+=("$1"); shift ;;
            esac
        done
        [[ "$repo" == true && "${#paths[@]}" -gt 0 ]] || exit 95
        release_exists || exit 96
        for path in "${paths[@]}"; do
            name="$(basename "$path")"
            grep -F -x -q -- "$name" "$MOCK_EXPECTED_ASSETS" || exit 97
            if grep -F -x -q -- "$name" "$MOCK_STATE_DIR/asset-names"; then
                exit 98
            fi
            [[ -f "$path" && ! -L "$path" ]] || exit 99
            cmp -s "$path" "$MOCK_CANDIDATE_DIR/$name" || exit 100
        done
        if [[ "$MOCK_SCENARIO" == interrupted-upload ]]; then
            printf 'upload-partial\n' >>"$MOCK_MUTATION_LOG"
        else
            printf 'upload\n' >>"$MOCK_MUTATION_LOG"
        fi
        uploaded=0
        for path in "${paths[@]}"; do
            name="$(basename "$path")"
            /bin/cp -- "$path" "$MOCK_REMOTE_ASSETS/$name"
            printf '%s\n' "$name" >>"$MOCK_STATE_DIR/asset-names"
            uploaded=$((uploaded + 1))
            if [[ "$MOCK_SCENARIO" == interrupted-upload && "$uploaded" == 3 ]]; then
                exit 107
            fi
        done
        ;;
    "release download")
        [[ "$3" == "$MOCK_TAG" ]] || exit 101
        shift 3
        repo=false
        destination=""
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                --repo)
                    [[ "${2:-}" == github.com/GGULBAE/desk-setup-switcher ]] || exit 102
                    repo=true
                    shift 2
                    ;;
                --dir) destination="${2:-}"; shift 2 ;;
                --clobber) exit 103 ;;
                *) exit 104 ;;
            esac
        done
        [[ "$repo" == true && -d "$destination" && ! -L "$destination" ]] || exit 105
        first=true
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            if [[ "$first" == true && "$MOCK_SCENARIO" == downloaded-symlink ]]; then
                ln -s "$MOCK_REMOTE_ASSETS/$name" "$destination/$name"
            elif [[ "$first" == true && "$MOCK_SCENARIO" == downloaded-nonregular ]]; then
                mkdir "$destination/$name"
            else
                /bin/cp -- "$MOCK_REMOTE_ASSETS/$name" "$destination/$name"
                if [[ "$first" == true && "$MOCK_SCENARIO" == mismatched-asset ]]; then
                    printf 'tamper\n' >>"$destination/$name"
                fi
            fi
            first=false
        done <"$MOCK_STATE_DIR/asset-names"
        ;;
    *) exit 106 ;;
esac
MOCK_GH

chmod 0755 "$mock_bin/dirname" "$mock_bin/ruby" "$mock_bin/cp" "$mock_bin/git" "$mock_bin/gh"

expected_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
master_commit=cccccccccccccccccccccccccccccccccccccccc
final_evidence_commit=dddddddddddddddddddddddddddddddddddddddd
final_evidence_path="docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json"
candidate_manual_path="docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json"
publication_manual_path="docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json"
manual_fixture_root="$temporary_root/final-manual-fixtures"
candidate_manual_source="$manual_fixture_root/release-candidate-admin-bypass.json"
publication_manual_source="$manual_fixture_root/release-publication-admin-token-scope.json"
final_evidence_source="$manual_fixture_root/remote-controls-final-pre-tag.json"
mkdir -m 0700 "$manual_fixture_root"
"$real_ruby" -rjson -rdigest -e '
  evidence_fixture, evidence_output, candidate_output, publication_output = ARGV
  actor = { "id" => 1001, "login" => "synthetic-operator", "type" => "User" }
  base = {
    "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
    "phase" => "final-pre-tag",
    "observedAt" => "2026-07-17T23:30:00Z",
    "observer" => actor,
    "administratorBypassEnabled" => false,
    "redactionReviewed" => true,
    "subject" => { "tag" => "v0.1.0" }
  }
  candidate = base.merge(
    "control" => "release-candidate-administrator-bypass-disabled",
    "sourceArtifactSHA256" => "1" * 64,
    "tokenPermissions" => [],
    "token" => nil
  )
  publication = base.merge(
    "control" => "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
    "sourceArtifactSHA256" => "2" * 64,
    "tokenPermissions" => %w[actions:read administration:read attestations:read contents:read metadata:read],
    "token" => {
      "type" => "fine-grained-personal-access-token",
      "resourceOwner" => "synthetic-operator",
      "repositorySelection" => ["synthetic-operator/desk-setup-switcher"],
      "accountPermissions" => [],
      "organizationPermissions" => [],
      "issuedAt" => "2026-07-17T23:20:00Z",
      "expiresAt" => "2026-08-16T00:00:00Z"
    }
  )
  File.binwrite(candidate_output, JSON.generate(candidate) + "\n")
  File.binwrite(publication_output, JSON.generate(publication) + "\n")
  evidence = JSON.parse(File.binread(evidence_fixture), allow_nan: false)
  items = evidence.fetch("manualEvidence").fetch("items")
  items.fetch(0)["sha256"] = Digest::SHA256.file(candidate_output).hexdigest
  items.fetch(1)["sha256"] = Digest::SHA256.file(publication_output).hexdigest
  File.binwrite(evidence_output, JSON.pretty_generate(evidence) + "\n")
' "$ROOT_DIR/scripts/release/fixtures/remote-controls/evidence-v2-final-pre-tag.json" \
    "$final_evidence_source" "$candidate_manual_source" "$publication_manual_source"
final_evidence_digest="$(shasum -a 256 "$final_evidence_source" | awk '{print $1}')"
tag="v$VERSION"
notes_relative="docs/releases/$tag.md"
notes_path="$ROOT_DIR/$notes_relative"
title="Desk Setup Switcher $tag public beta"
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
candidate_directory=""
download_directory=""
mutation_log=""
command_log=""

setup_case() {
    local scenario="$1"
    local name
    case_index=$((case_index + 1))
    case_root="$temporary_root/case-$case_index-$scenario"
    candidate_directory="$case_root/candidate"
    download_directory="$case_root/runner/final-download"
    mutation_log="$case_root/mutations.log"
    command_log="$case_root/commands.log"
    mkdir -p "$candidate_directory" "$case_root/runner" "$case_root/state" "$case_root/remote-assets"
    : >"$mutation_log"
    : >"$command_log"
    : >"$case_root/secret-probe.log"
    : >"$case_root/state/asset-names"
    printf '0\n' >"$case_root/state/exists"
    printf '%s\n' "${asset_names[@]}" >"$case_root/expected-assets"
    for name in "${asset_names[@]}"; do
        printf 'exact candidate asset: %s\n' "$name" >"$candidate_directory/$name"
    done

    case "$scenario" in
        absent|interrupted-upload|api-failure|remote-tag-drift|remote-tag-object-drift|remote-peeled-missing|local-lightweight-tag|local-extra|local-symlink|local-nonregular|final-evidence-two-introductions|final-evidence-merge-introduction|final-evidence-second-parent|final-evidence-extra-path|final-evidence-blob-drift|final-evidence-critical-tree-drift|final-evidence-tag-digest-mismatch|final-evidence-invalid) ;;
        partial|mismatched-asset)
            printf '1\n' >"$case_root/state/exists"
            printf '%s\n' "${asset_names[0]}" "${asset_names[1]}" >"$case_root/state/asset-names"
            cp -- "$candidate_directory/${asset_names[0]}" "$case_root/remote-assets/${asset_names[0]}"
            cp -- "$candidate_directory/${asset_names[1]}" "$case_root/remote-assets/${asset_names[1]}"
            ;;
        extra-asset)
            printf '1\n' >"$case_root/state/exists"
            printf '%s\n' "${asset_names[0]}" unexpected.txt >"$case_root/state/asset-names"
            cp -- "$candidate_directory/${asset_names[0]}" "$case_root/remote-assets/${asset_names[0]}"
            printf 'unexpected\n' >"$case_root/remote-assets/unexpected.txt"
            ;;
        duplicate-asset)
            printf '1\n' >"$case_root/state/exists"
            printf '%s\n' "${asset_names[0]}" "${asset_names[0]}" >"$case_root/state/asset-names"
            cp -- "$candidate_directory/${asset_names[0]}" "$case_root/remote-assets/${asset_names[0]}"
            ;;
        complete|published|not-prerelease|title-mismatch|notes-mismatch|downloaded-symlink|downloaded-nonregular)
            printf '1\n' >"$case_root/state/exists"
            printf '%s\n' "${asset_names[@]}" >"$case_root/state/asset-names"
            for name in "${asset_names[@]}"; do
                cp -- "$candidate_directory/$name" "$case_root/remote-assets/$name"
            done
            ;;
        *) fail "Unknown mock draft scenario: $scenario" ;;
    esac

    case "$scenario" in
        local-extra) printf 'extra\n' >"$candidate_directory/unexpected.txt" ;;
        local-symlink)
            rm -f -- "$candidate_directory/${asset_names[0]}"
            ln -s "$candidate_directory/${asset_names[1]}" "$candidate_directory/${asset_names[0]}"
            ;;
        local-nonregular)
            rm -f -- "$candidate_directory/${asset_names[0]}"
            mkdir "$candidate_directory/${asset_names[0]}"
            ;;
    esac
}

run_target_with_attempts() {
    local scenario="$1"
    local current_attempt="$2"
    local candidate_attempt="$3"
    local candidate_run_id="${4:-12000}"
    local gh_token="${5-$runtime_gh_token}"
    env -i \
        "PATH=$mock_bin:$PATH" \
        "HOME=${HOME:-/tmp}" \
        "TMPDIR=${TMPDIR:-/tmp}" \
        "DEVELOPER_DIR=$DEVELOPER_DIR" \
        DESK_SETUP_RELEASE_MUTATIONS=1 \
        GITHUB_ACTIONS=true \
        GITHUB_EVENT_NAME=workflow_dispatch \
        GITHUB_REF_TYPE=tag \
        "GITHUB_REF=refs/tags/$tag" \
        "GITHUB_REF_NAME=$tag" \
        RELEASE_PROTECTED_ENVIRONMENT=release-candidate \
        GITHUB_REPOSITORY=GGULBAE/desk-setup-switcher \
        GITHUB_RUN_ID=12345 \
        "GITHUB_RUN_ATTEMPT=$current_attempt" \
        "RELEASE_CANDIDATE_RUN_ID=$candidate_run_id" \
        "RELEASE_CANDIDATE_RUN_ATTEMPT=$candidate_attempt" \
        RUNNER_ENVIRONMENT=github-hosted \
        "RUNNER_TEMP=$case_root/runner" \
        "GH_TOKEN=$gh_token" \
        "GITHUB_TOKEN=$runtime_github_alias_token" \
        "github_token=$runtime_lowercase_alias_token" \
        "RELEASE_TAG=$tag" \
        "EXPECTED_COMMIT=$expected_commit" \
        "RELEASE_CONFIRMATION=prepare signed draft $tag" \
        "RELEASE_NOTES_PATH=$notes_relative" \
        "RELEASE_SOURCE_DIR=$candidate_directory" \
        "RELEASE_DOWNLOAD_DIR=$download_directory" \
        "MOCK_ROOT_DIR=$ROOT_DIR" \
        "MOCK_EXPECTED_COMMIT=$expected_commit" \
        "MOCK_TAG_OBJECT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
        "MOCK_MASTER_COMMIT=$master_commit" \
        "MOCK_FINAL_EVIDENCE_COMMIT=$final_evidence_commit" \
        "MOCK_FINAL_EVIDENCE_PATH=$final_evidence_path" \
        "MOCK_FINAL_EVIDENCE_DIGEST=$final_evidence_digest" \
        "MOCK_FINAL_EVIDENCE_SOURCE=$final_evidence_source" \
        "MOCK_POLICY_SOURCE=$ROOT_DIR/scripts/release/fixtures/remote-controls/policy-v2.json" \
        "MOCK_POLICY_VALIDATOR_SOURCE=$ROOT_DIR/scripts/release/remote_controls_policy.rb" \
        "MOCK_RELEASE_POLICY_SOURCE=$ROOT_DIR/scripts/release/release_policy.rb" \
        "MOCK_COLLECTOR_SOURCE=$ROOT_DIR/scripts/release/collect_remote_controls_evidence.rb" \
        "MOCK_CANDIDATE_MANUAL_PATH=$candidate_manual_path" \
        "MOCK_PUBLICATION_MANUAL_PATH=$publication_manual_path" \
        "MOCK_CANDIDATE_MANUAL_SOURCE=$candidate_manual_source" \
        "MOCK_PUBLICATION_MANUAL_SOURCE=$publication_manual_source" \
        "MOCK_CANDIDATE_WORKFLOW_BLOB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
        "MOCK_CI_WORKFLOW_BLOB=cccccccccccccccccccccccccccccccccccccccc" \
        "MOCK_PUBLICATION_WORKFLOW_BLOB=dddddddddddddddddddddddddddddddddddddddd" \
        "MOCK_TAG=$tag" \
        "MOCK_SCENARIO=$scenario" \
        "MOCK_RELEASE_NOTES_RELATIVE=$notes_relative" \
        "MOCK_RELEASE_NOTES_PATH=$notes_path" \
        "MOCK_TITLE=$title" \
        "MOCK_STATE_DIR=$case_root/state" \
        "MOCK_REMOTE_ASSETS=$case_root/remote-assets" \
        "MOCK_EXPECTED_ASSETS=$case_root/expected-assets" \
        "MOCK_CANDIDATE_DIR=$candidate_directory" \
        "MOCK_MUTATION_LOG=$mutation_log" \
        "MOCK_COMMAND_LOG=$command_log" \
        "MOCK_SECRET_PROBE=$case_root/secret-probe.log" \
        "MOCK_EXPECTED_GH_TOKEN_SHA256=$runtime_gh_token_sha256" \
        "MOCK_REAL_RUBY=$real_ruby" \
        "$RELEASE_SCRIPTS_DIR/prepare-draft-release.sh"
}

run_target() {
    run_target_with_attempts "$1" 2 1
}

assert_exact_final_download() {
    local name
    [[ -d "$download_directory" && ! -L "$download_directory" ]] || fail "Successful draft run did not retain its final download."
    ruby -e '
      expected_file, directory = ARGV
      expected = File.readlines(expected_file, chomp: true)
      actual = Dir.children(directory)
      abort unless actual.sort == expected.sort
      actual.each do |name|
        stat = File.lstat(File.join(directory, name))
        abort unless stat.file? && !stat.symlink?
      end
    ' "$case_root/expected-assets" "$download_directory" || fail "Final draft download is not the exact regular nine-asset set."
    for name in "${asset_names[@]}"; do
        cmp -s "$candidate_directory/$name" "$download_directory/$name" || fail "Final draft asset differs: $name"
    done
    pass
}

assert_no_forbidden_command() {
    if grep -E -q -- '--clobber|release (edit|delete|publish|view)' "$command_log"; then
        fail "Draft helper invoked a forbidden replacement or state-changing command."
    fi
    pass
}

assert_secret_isolation_probe() {
    local command_name
    for command_name in dirname git ruby cp; do
        grep -F -x -q -- "$command_name" "$case_root/secret-probe.log" || {
            fail "The credential-isolation probe did not reach $command_name."
        }
    done
    pass
}

run_success_case() {
    local scenario="$1"
    local expected_mutations="$2"
    setup_case "$scenario"
    if ! run_target "$scenario" >"$case_root/stdout" 2>"$case_root/stderr"; then
        printf 'Unexpected %s stderr:\n' "$scenario" >&2
        sed -n '1,80p' "$case_root/stderr" >&2
        fail "Expected draft scenario failed: $scenario"
    fi
    [[ "$(tr -d '\n' <"$mutation_log")" == "$expected_mutations" ]] || fail "Unexpected mutation sequence for $scenario."
    pass
    assert_exact_final_download
    assert_no_forbidden_command
    assert_secret_isolation_probe
}

run_failure_case() {
    local scenario="$1"
    setup_case "$scenario"
    if run_target "$scenario" >"$case_root/stdout" 2>"$case_root/stderr"; then
        fail "Unsafe draft scenario unexpectedly succeeded: $scenario"
    fi
    [[ ! -s "$mutation_log" ]] || fail "A failing draft scenario performed a remote mutation: $scenario"
    [[ ! -e "$download_directory" && ! -L "$download_directory" ]] || fail "A failing draft scenario exposed a final download: $scenario"
    if grep -F -q 'SENSITIVE_REMOTE_MARKER' "$case_root/stdout" "$case_root/stderr"; then
        fail "A failing draft scenario exposed a raw remote response: $scenario"
    fi
    pass
    assert_no_forbidden_command
}

run_success_case absent createupload
run_success_case complete ''
run_success_case partial upload

# Simulate the resumable interruption itself: the release is created empty,
# three exact assets reach GitHub, and the upload command fails. The helper must
# expose no final download. A rerun then uploads only the six still-missing names.
setup_case interrupted-upload
if run_target interrupted-upload >"$case_root/first.stdout" 2>"$case_root/first.stderr"; then
    fail "Interrupted upload unexpectedly completed."
fi
[[ "$(tr -d '\n' <"$mutation_log")" == createupload-partial ]] || {
    fail "Interrupted upload did not retain the expected additive partial state."
}
[[ ! -e "$download_directory" && ! -L "$download_directory" ]] || {
    fail "Interrupted upload exposed an unverified final download."
}
[[ "$(wc -l <"$case_root/state/asset-names" | tr -d '[:space:]')" == 3 ]] || {
    fail "Interrupted upload did not retain exactly three uploaded assets."
}
pass
: >"$mutation_log"
run_target partial >"$case_root/resume.stdout" 2>"$case_root/resume.stderr" || {
    sed -n '1,80p' "$case_root/resume.stderr" >&2
    fail "A retained partial draft could not resume."
}
[[ "$(tr -d '\n' <"$mutation_log")" == upload ]] || {
    fail "Partial rerun did not use one missing-only upload."
}
[[ "$(wc -l <"$case_root/state/asset-names" | tr -d '[:space:]')" == 9 ]] || {
    fail "Partial rerun did not complete the exact nine assets."
}
pass
assert_exact_final_download
assert_no_forbidden_command
assert_secret_isolation_probe

for scenario in \
    mismatched-asset \
    extra-asset \
    duplicate-asset \
    published \
    not-prerelease \
    title-mismatch \
    notes-mismatch \
    api-failure \
    remote-tag-drift \
    remote-tag-object-drift \
    remote-peeled-missing \
    local-lightweight-tag \
    downloaded-symlink \
    downloaded-nonregular \
    local-extra \
    local-symlink \
    local-nonregular; do
    run_failure_case "$scenario"
done

for scenario in \
    final-evidence-two-introductions \
    final-evidence-merge-introduction \
    final-evidence-second-parent \
    final-evidence-extra-path \
    final-evidence-blob-drift \
    final-evidence-critical-tree-drift \
    final-evidence-tag-digest-mismatch \
    final-evidence-invalid; do
    run_failure_case "$scenario"
done

# Candidate provenance must always remain pinned to attempt 1, while a current
# retry may have a larger positive attempt number.
setup_case absent
if run_target_with_attempts absent 2 2 >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "A non-attempt-1 candidate origin was accepted."
fi
[[ ! -s "$mutation_log" ]] || fail "Attempt-origin rejection performed a remote mutation."
pass

setup_case absent
if run_target_with_attempts absent 0 1 >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "An invalid current workflow attempt was accepted."
fi
[[ ! -s "$mutation_log" ]] || fail "Current-attempt rejection performed a remote mutation."
pass

setup_case absent
if run_target_with_attempts absent 1 1 12345 >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "The current draft run was accepted as its own candidate origin."
fi
[[ ! -s "$mutation_log" ]] || fail "Same-run origin rejection performed a remote mutation."
pass

# Neither GITHUB_TOKEN nor an inherited lowercase github_token may substitute
# for the explicitly captured GH_TOKEN credential.
setup_case absent
if run_target_with_attempts absent 2 1 12000 "" >"$case_root/stdout" 2>"$case_root/stderr"; then
    fail "Inherited GitHub token aliases were accepted without GH_TOKEN."
fi
[[ ! -s "$mutation_log" ]] || fail "Token-alias rejection performed a remote mutation."
pass

printf 'Draft release reconciler mock tests passed (%d assertions).\n' "$assertions"
