#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

set +e
shallow_repository="$(git rev-parse --is-shallow-repository 2>/dev/null)"
git_status=$?
set -e
if [[ "$git_status" != 0 ]]; then
    echo "Public-release Git history audit could not inspect repository data." >&2
    exit 1
fi
if [[ "$shallow_repository" == "true" ]]; then
    echo "Public-release history audit requires a complete Git checkout." >&2
    echo "Fetch full history before retrying (for Actions checkout, use fetch-depth: 0)." >&2
    exit 1
fi

secret_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-secret-hits.XXXXXX")"
home_path_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-home-hits.XXXXXX")"
image_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-image-hits.XXXXXX")"
privacy_hits="$(mktemp "${TMPDIR:-/tmp}/desk-setup-privacy-hits.XXXXXX")"
git_scan_output="$(mktemp "${TMPDIR:-/tmp}/desk-setup-git-scan.XXXXXX")"
git_scan_aux="$(mktemp "${TMPDIR:-/tmp}/desk-setup-git-scan-aux.XXXXXX")"

cleanup() {
    rm -f \
        "$secret_hits" \
        "$home_path_hits" \
        "$image_hits" \
        "$privacy_hits" \
        "$git_scan_output" \
        "$git_scan_aux"
}
trap cleanup EXIT

fail_git_history_audit() {
    echo "Public-release Git history audit could not inspect repository data." >&2
    exit 1
}

capture_git_grep() {
    local output_path="$1"
    shift
    local status=0
    set +e
    git grep "$@" >"$output_path" 2>/dev/null
    status=$?
    set -e
    case "$status" in
        0|1) return 0 ;;
        *) fail_git_history_audit ;;
    esac
}

capture_git_command() {
    local output_path="$1"
    shift
    if ! git "$@" >"$output_path" 2>/dev/null; then
        fail_git_history_audit
    fi
}

# Legacy credential/home/image collectors predate value-aware findings. Always
# render their path field as an opaque digest so a credential-shaped filename,
# colon, quote, or control character cannot escape the values-suppressed boundary.
render_opaque_finding_metadata() {
    ruby -rdigest -e '
      begin
        records = []
        STDIN.each_line do |line|
          raw = line.chomp.b
          next if raw.empty?
          prefix = raw[/\A(?:WORKTREE|[0-9a-f]{40,64})(?=:)/] || "UNKNOWN"
          digest = Digest::SHA256.hexdigest(raw)[0, 16]
          records << "#{prefix}:path-digest-#{digest}"
        end
        records.uniq.sort.each { |record| puts record }
      rescue StandardError
        exit 2
      end
    '
}

# Keep this list deliberately narrow and high-confidence. The audit reports only
# commit/path metadata so a suspected credential is never echoed back to logs.
secret_pattern='(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|github_pat_[0-9A-Za-z_]{20,}|gh[pousr]_[0-9A-Za-z]{20,}|(^|[^A-Za-z0-9])sk-(proj-)?[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,})'
private_key_header_pattern='-----BEGIN '
mac_home_prefix='/''Users/'
home_path_pattern="${mac_home_prefix}"'[A-Za-z0-9._-]+/[^[:space:]]+'

contains_concrete_home_path() {
    local scanner_status=0
    ruby -e '
      begin
        prefix = "/" + "Users/"
        pattern = Regexp.new(Regexp.escape(prefix) + "([A-Za-z0-9._-]+)/[^\\s]+")
        found = STDIN.read.scan(pattern).any? { |captures| captures.first.downcase != "example" }
        exit(found ? 0 : 1)
      rescue StandardError
        exit 2
      end
    ' || scanner_status=$?
    case "$scanner_status" in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

# A PEM marker can legitimately appear in validation code. Require a plausible
# base64 body and matching footer, in either plain or escaped form, so embedded
# JSON/environment values still fail without allowlisting release-tooling paths.
contains_private_key_material() {
    local scanner_status=0
    ruby -e '
      content = STDIN.read.b
      label = "((?:(?:RSA|EC|OPENSSH|DSA|ENCRYPTED) )?PRIVATE KEY)"
      legacy_plain = "(?:Proc-Type:[ \\t]*4,ENCRYPTED\\r?\\nDEK-Info:[ \\t]*[A-Z0-9-]+,[0-9A-Fa-f]+\\r?\\n(?:\\r?\\n)?)?"
      legacy_escaped = "(?:Proc-Type:[ \\t]*4,ENCRYPTED(?:\\\\r)?\\\\nDEK-Info:[ \\t]*[A-Z0-9-]+,[0-9A-Fa-f]+(?:\\\\r)?\\\\n(?:(?:\\\\r)?\\\\n)?)?"
      body_plain = "[A-Za-z0-9+/]{16,}={0,2}\\r?\\n(?:[A-Za-z0-9+/]{4,}={0,2}\\r?\\n)*"
      body_escaped = "[A-Za-z0-9+/]{16,}={0,2}(?:\\\\r)?\\\\n(?:[A-Za-z0-9+/]{4,}={0,2}(?:\\\\r)?\\\\n)*"
      plain = Regexp.new(
        "-----BEGIN #{label}-----\\r?\\n#{legacy_plain}#{body_plain}-----END \\1-----",
        Regexp::NOENCODING
      )
      escaped = Regexp.new(
        "-----BEGIN #{label}-----(?:\\\\r)?\\\\n#{legacy_escaped}#{body_escaped}-----END \\1-----",
        Regexp::NOENCODING
      )
      escaped_content = content.gsub(%q(\/).b, "/".b)
      exit(plain.match?(content) || escaped.match?(escaped_content) ? 0 : 3)
    ' || scanner_status=$?
    case "$scanner_status" in
        0) return 0 ;;
        3) return 1 ;;
        *)
            echo "Public-release credential material scanner failed closed." >&2
            return 0
            ;;
    esac
}

# Fail closed if future edits weaken either the detector or its false-positive
# boundary. These probes are generated in memory and never printed or persisted.
private_key_marker='PRIVATE KEY'
private_key_body='QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo='
private_key_escaped_solidus_body='QUJDREVGR0hJSktMTU5P\/Q=='
encrypted_private_key_marker='RSA PRIVATE KEY'
private_key_dek='AES-256-CBC,00112233445566778899AABBCCDDEEFF'
{
    printf '%s\n' "-----BEGIN $private_key_marker-----"
    printf '%s\n' "$private_key_body"
    printf '%s\n' "-----END $private_key_marker-----"
} | contains_private_key_material || {
    echo "Public-release credential audit failed its plain PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $private_key_marker-----\\n${private_key_body}\\n-----END $private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $private_key_marker-----\\n${private_key_escaped_solidus_body}\\n-----END $private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped-solidus PEM self-check." >&2
    exit 1
}
{
    printf '%s\n' "-----BEGIN $encrypted_private_key_marker-----"
    printf '%s\n' 'Proc-Type: 4,ENCRYPTED'
    printf 'DEK-Info: %s\n\n' "$private_key_dek"
    printf '%s\n' "$private_key_body"
    printf '%s\n' "-----END $encrypted_private_key_marker-----"
} | contains_private_key_material || {
    echo "Public-release credential audit failed its encrypted PEM self-check." >&2
    exit 1
}
printf '%s\n' "{\"private_key\":\"-----BEGIN $encrypted_private_key_marker-----\\nProc-Type: 4,ENCRYPTED\\nDEK-Info: ${private_key_dek}\\n\\n${private_key_body}\\n-----END $encrypted_private_key_marker-----\\n\"}" \
    | contains_private_key_material || {
    echo "Public-release credential audit failed its escaped encrypted PEM self-check." >&2
    exit 1
}
if printf '%s\n' "grep -q '^-----BEGIN $private_key_marker-----$'" \
    | contains_private_key_material; then
    echo "Public-release credential audit matched a marker-only validator." >&2
    exit 1
fi

# Include tracked working-tree content so the command is useful before the
# release-preparation commit as well as after it. Only path metadata is kept.
capture_git_grep "$git_scan_output" -z -I -l -E "$secret_pattern" -- .
while IFS= read -r -d '' path; do
    printf 'WORKTREE:%s\n' "$path" >>"$secret_hits"
done <"$git_scan_output"

capture_git_grep \
    "$git_scan_output" \
    -z -I -l -F -e "$private_key_header_pattern" -- .
while IFS= read -r -d '' path; do
    if [[ ! -f "$path" || -L "$path" ]] || contains_private_key_material <"$path"; then
        printf 'WORKTREE:%s\n' "$path" >>"$secret_hits"
    fi
done <"$git_scan_output"

capture_git_grep "$git_scan_output" -z -I -l -E "$home_path_pattern" -- .
while IFS= read -r -d '' path; do
    if [[ ! -f "$path" || -L "$path" ]]; then
        printf 'WORKTREE:%s\n' "$path" >>"$home_path_hits"
        continue
    fi
    set +e
    contains_concrete_home_path <"$path"
    home_status=$?
    set -e
    [[ "$home_status" == 0 || "$home_status" == 1 ]] || fail_git_history_audit
    if [[ "$home_status" == 0 ]]; then
        printf 'WORKTREE:%s\n' "$path" >>"$home_path_hits"
    fi
done <"$git_scan_output"

capture_git_command "$git_scan_aux" rev-list --all
while IFS= read -r commit; do
    capture_git_grep "$git_scan_output" -z -I -l -E "$secret_pattern" "$commit" --
    while IFS= read -r -d '' candidate; do
        printf '%s\n' "$candidate" >>"$secret_hits"
    done <"$git_scan_output"

    capture_git_grep \
        "$git_scan_output" \
        -z -I -l -F -e "$private_key_header_pattern" "$commit" --
    while IFS= read -r -d '' candidate; do
        path="${candidate#*:}"
        set +e
        git show "${commit}:${path}" 2>/dev/null | contains_private_key_material
        pipeline_status=("${PIPESTATUS[@]}")
        set -e
        [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
        if [[ "${pipeline_status[1]}" == 0 ]]; then
            printf '%s:%s\n' "$commit" "$path" >>"$secret_hits"
        fi
    done <"$git_scan_output"

    # The reserved example home is intentional synthetic redaction-test data. Any other
    # concrete macOS home path is unsuitable for public history.
    capture_git_grep "$git_scan_output" -z -I -l -E "$home_path_pattern" "$commit" --
    while IFS= read -r -d '' candidate; do
        path="${candidate#*:}"
        set +e
        git show "${commit}:${path}" 2>/dev/null | contains_concrete_home_path
        pipeline_status=("${PIPESTATUS[@]}")
        set -e
        [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
        [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
        if [[ "${pipeline_status[1]}" == 0 ]]; then
            printf '%s:%s\n' "$commit" "$path" >>"$home_path_hits"
        fi
    done <"$git_scan_output"

    set +e
    git show -s --format='%B' "$commit" 2>/dev/null | grep -E "$secret_pattern" >/dev/null
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$commit" 'commit-message' >>"$secret_hits"
    fi

    set +e
    git show -s --format='%B' "$commit" 2>/dev/null | contains_private_key_material
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$commit" 'commit-message' >>"$secret_hits"
    fi

    set +e
    git show -s --format='%B' "$commit" 2>/dev/null | contains_concrete_home_path
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$commit" 'commit-message' >>"$home_path_hits"
    fi
done <"$git_scan_aux"

# Annotated tag messages are separate Git objects and are not returned as commit
# bodies. Scan message bodies without ever placing them in a shell variable or log.
capture_git_command \
    "$git_scan_aux" \
    for-each-ref --format='%(objecttype) %(objectname)' refs/tags
while read -r object_type object; do
    [[ "$object_type" == "tag" && "$object" =~ ^[0-9a-f]{40,64}$ ]] || continue
    tag_message() {
        git cat-file tag "$object" 2>/dev/null | awk 'body { print } /^$/ { body = 1 }'
    }
    set +e
    tag_message | grep -E "$secret_pattern" >/dev/null
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$object" 'tag-message' >>"$secret_hits"
    fi

    set +e
    tag_message | contains_private_key_material
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$object" 'tag-message' >>"$secret_hits"
    fi

    set +e
    tag_message | contains_concrete_home_path
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
    if [[ "${pipeline_status[1]}" == 0 ]]; then
        printf '%s:%s\n' "$object" 'tag-message' >>"$home_path_hits"
    fi
done <"$git_scan_aux"

# Inspect tracked working-tree images and every historical image blob. strings
# is intentionally used as a conservative metadata/path detector; image pixels
# are reviewed separately through the checked-in synthetic evidence process.
capture_git_command "$git_scan_aux" ls-files -z
if ! ruby -e '
  begin
    STDIN.read.b.split("\0").each do |path|
      STDOUT.write(path, "\0") if path.match?(/\.(?:gif|jpe?g|icns|mov|mp4|pdf|png|webm)\z/i)
    end
  rescue StandardError
    exit 2
  end
' <"$git_scan_aux" >"$git_scan_output"; then
    fail_git_history_audit
fi
while IFS= read -r -d '' path; do
    if [[ ! -f "$path" || -L "$path" ]]; then
        printf 'WORKTREE:%s\n' "$path" >>"$image_hits"
        continue
    fi
    set +e
    strings "$path" 2>/dev/null \
        | grep -E "$secret_pattern|$home_path_pattern|/home/[^/[:space:]]+/" >/dev/null
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 || "${pipeline_status[1]}" == 1 ]] || fail_git_history_audit
    image_match="${pipeline_status[1]}"

    set +e
    strings "$path" 2>/dev/null | contains_private_key_material
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    if [[ "$image_match" == 0 || "${pipeline_status[1]}" == 0 ]]; then
        printf 'WORKTREE:%s\n' "$path" >>"$image_hits"
    fi
done <"$git_scan_output"

capture_git_command "$git_scan_aux" rev-list --objects --all -z
if ! ruby -e '
  begin
    pending_object = nil
    STDIN.read.b.split("\0").each do |entry|
      object, path = entry.split(" ", 2)
      if object&.match?(/\A[0-9a-f]{40,64}\z/)
        pending_object = object
        if path
          if path.match?(/\.(?:gif|jpe?g|icns|mov|mp4|pdf|png|webm)\z/i)
            STDOUT.write(object, "\0", path, "\0")
          end
          pending_object = nil
        end
      elsif pending_object && entry.start_with?("path=")
        path = entry.byteslice(5, entry.bytesize - 5)
        if path && path.match?(/\.(?:gif|jpe?g|icns|mov|mp4|pdf|png|webm)\z/i)
          STDOUT.write(pending_object, "\0", path, "\0")
        end
        pending_object = nil
      end
    end
  rescue StandardError
    exit 2
  end
' <"$git_scan_aux" >"$git_scan_output"; then
    fail_git_history_audit
fi
while IFS= read -r -d '' object && IFS= read -r -d '' path; do
    set +e
    git cat-file blob "$object" 2>/dev/null \
        | strings \
        | grep -E "$secret_pattern|$home_path_pattern|/home/[^/[:space:]]+/" >/dev/null
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[2]}" == 0 || "${pipeline_status[2]}" == 1 ]] || fail_git_history_audit
    image_match="${pipeline_status[2]}"

    set +e
    git cat-file blob "$object" 2>/dev/null | strings | contains_private_key_material
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    [[ "${pipeline_status[0]}" == 0 ]] || fail_git_history_audit
    [[ "${pipeline_status[1]}" == 0 ]] || fail_git_history_audit
    if [[ "$image_match" == 0 || "${pipeline_status[2]}" == 0 ]]; then
        printf '%s:%s\n' "$object" "$path" >>"$image_hits"
    fi
done <"$git_scan_output"

# Scan tracked working-tree content and every relevant historical blob for
# privacy-sensitive literals that are not credential shaped. The scanner emits
# source/path/category metadata only; matched values never reach stdout/stderr.
# Documentation address blocks and explicitly marked synthetic fixture context
# are allowed, while private/link-local/global host literals fail closed.
if ! ruby -ropen3 -ripaddr -rset -rdigest -e '
  root, output_path = ARGV
  begin

  TEXT_EXTENSIONS = Set.new(%w[
    .bash .c .cc .cfg .conf .config .cpp .css .csv .entitlements .env .example
    .h .hpp .html .ini .js .json .jsx .lock .m .md .mjs .mm .mts .pbxproj
    .plist .properties .py .rb .resolved .rs .sh .sha256 .srt .strings .svg
    .swift .toml .ts .tsx .txt .vtt .xcconfig .xcscheme .xml .yaml .yml .zsh
  ]).freeze
  ASSET_EXTENSIONS = Set.new(%w[
    .gif .icns .jpeg .jpg .mov .mp4 .pdf .png .svg .webm
  ]).freeze
  EXTENSIONLESS_TEXT = Set.new(%w[
    .gitattributes .gitignore AGENTS.md CHANGELOG CODE_OF_CONDUCT CONTRIBUTING
    Dockerfile GOVERNANCE LICENSE Makefile README SECURITY SUPPORT
  ]).freeze
  SKIPPED_PREFIXES = %w[
    .build/ .git/ artifacts/ site/.next/ site/.wrangler/ site/dist/ site/node_modules/
  ].freeze
  SOURCE_EXTENSIONS = Set.new(%w[
    .c .cc .cpp .h .hpp .js .jsx .m .mm .rb .rs .swift .ts .tsx
  ]).freeze
  # Exact legacy blob/path/category findings are accepted only after reviewing
  # their surrounding source against the repository synthetic-data policy. New
  # content at the same path, or a new finding category, inherits no exception.
  REVIEWED_SYNTHETIC_FINDINGS = Set.new([
    # Removed condition editor: one synthetic default region (coordinates).
    ["987c19ec4be9e7910fbec2a1a5b626864a08dae9", "Sources/DeskSetupSwitcher/ConditionEditorView.swift", "coordinates"],
    # UI audit host: one reviewed synthetic manual-network fixture (IP host).
    ["6035be8b7e48e168cb9817da2e73470931ba621d", "Sources/DeskSetupSwitcher/UIAuditFixtures.swift", "ip-host"],
    # Applicability normalization fixtures: three historical synthetic host sets.
    ["0744ebd07210d65e95ac32d9ea32963ed96d6dcd", "Tests/DeskSetupCoreTests/ProfileApplicabilityNormalizerTests.swift", "ip-host"],
    ["1fcbd3d948886a7986a5d6eb4c4553e26049cd26", "Tests/DeskSetupCoreTests/ProfileApplicabilityNormalizerTests.swift", "ip-host"],
    ["d54d17d20981ffc6b8ff9b99436b562d835c9fe0", "Tests/DeskSetupCoreTests/ProfileApplicabilityNormalizerTests.swift", "ip-host"],
    # Profile validation fixtures: three historical coordinate + host sets.
    ["233327bf3e07ca38febdda8d7136ecc703b1c5a6", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "coordinates"],
    ["233327bf3e07ca38febdda8d7136ecc703b1c5a6", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "ip-host"],
    ["5bcf875d4a1b67613ce393779f273893916fb797", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "coordinates"],
    ["5bcf875d4a1b67613ce393779f273893916fb797", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "ip-host"],
    ["773c88714e90d28d9e98c6455a174fbdbf4e49a8", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "coordinates"],
    ["773c88714e90d28d9e98c6455a174fbdbf4e49a8", "Tests/DeskSetupCoreTests/ProfileValidationTests.swift", "ip-host"],
    # Core condition/evaluation fixtures: synthetic regions and CIDR boundary cases.
    ["20c90b490e841d337c93363aa0defe4ea6d9a100", "Tests/DeskSetupCoreTests/ConditionEvaluatorTests.swift", "coordinates"],
    ["db8d315288e935d1d71d70f90e4884c005a565bf", "Tests/DeskSetupCoreTests/CIDRTests.swift", "ip-host"],
    # Redaction/log fixtures deliberately carry private-looking hosts to prove removal.
    ["5297a29e2ae4d3f0fe312d22178ceee36eb1bae0", "Tests/DeskSetupCoreTests/RotatingDiagnosticLogTests.swift", "ip-host"],
    ["7bc0661eca4107f664f1fa17d76b4b6b7d255ac5", "Tests/DeskSetupCoreTests/SensitiveDataRedactorTests.swift", "ip-host"],
    # Presentation validation fixtures: boundary regions and network/netmask cases.
    ["0cb67cbfea98c600d91d7896a50e566b2ef193b7", "Tests/DeskSetupPresentationTests/ConditionPresentationTests.swift", "coordinates"],
    ["1aded4130b17b954dac079b25ca75be136f94647", "Tests/DeskSetupPresentationTests/ProfileDraftValidationTests.swift", "ip-host"],
    ["fb47abea94598d6e5700a02542c0d7fcfa2ad883", "Tests/DeskSetupPresentationTests/ProfileDraftValidationTests.swift", "ip-host"],
    # Apply handoff uses an arbitrary synthetic region and never reads live location.
    ["54465288cb2c9e6ba70b801b59f25a258cc329b5", "Tests/DeskSetupSwitcherTests/ApplicationModelApplyTests.swift", "coordinates"],
    # UI-audit catalog fixtures use named fake audio roles, never runtime identifiers.
    ["1f95dc85bae520b661e33c537605f2c8cf9f23a4", "Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift", "device-identifier"],
    ["44c7b116cb6cd8e35ead88917953eb7b502b35b1", "Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift", "device-identifier"],
    ["80fe384aa5e192ebd8c7ed2e63da373e1dce0c55", "Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift", "device-identifier"],
    ["a002e5046957710e9e066d9deda17eb6bd1b70f6", "Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift", "device-identifier"],
    ["a45b31f1fe6f3b4744b50b8ee5324411cba44688", "Tests/DeskSetupSwitcherTests/UIAuditSafetyTests.swift", "device-identifier"],
    # Runtime-context fixtures: reviewed synthetic host, region, and network-name sets.
    ["744af5fcef5933ba3c038e076d867957b218d2e3", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "ip-host"],
    ["744af5fcef5933ba3c038e076d867957b218d2e3", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "coordinates"],
    ["744af5fcef5933ba3c038e076d867957b218d2e3", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "ssid"],
    ["a112a64a3aa77d12d96600a7df9fc5111405eab1", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "ip-host"],
    ["a112a64a3aa77d12d96600a7df9fc5111405eab1", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "coordinates"],
    ["a112a64a3aa77d12d96600a7df9fc5111405eab1", "Tests/DeskSetupSystemTests/ConditionContextProviderTests.swift", "ssid"],
    # Authorized-location cache tests use a fixed arbitrary region and synthetic time.
    ["a8ddf95f47d9651a39eba378c646cc5406f65a44", "Tests/DeskSetupSystemTests/AuthorizedLocationCacheTests.swift", "coordinates"],
    # Network adapter fixtures: six historical synthetic host sets.
    ["21be30e699b559ae5ccb393702ab81335d54baec", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    ["2809f0bb73146688b6dd7fb95dbd32870cd92553", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    ["69679d9322511aa55e69df136770cbd0017b5db4", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    ["74e6109e290f841ba36140f17f9c34a902f0fc16", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    ["9d24038a4b80b9de1a17106c2666e54706e5e583", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    ["d1515acfcff87a30f1df2e35f1faab895ee08eb3", "Tests/DeskSetupSystemTests/NetworkAdapterTests.swift", "ip-host"],
    # End-to-end invariant fixture: one historical synthetic host set.
    ["23214b39846087c8ae5c274a060236dcf668a7bb", "Tests/DeskSetupSystemTests/VisibleSettingEndToEndInvariantTests.swift", "ip-host"],
    # The audit regression script deliberately generates private-looking probe
    # values. Exempt only these exact reviewed blobs; any edit at the same path
    # receives a new object ID and is scanned normally.
    ["fef644754e21169074c924ad95eeea834deeac67", "scripts/test-audit-public-release.sh", "device-identifier"],
    ["fef644754e21169074c924ad95eeea834deeac67", "scripts/test-audit-public-release.sh", "ip-host"],
    ["fef644754e21169074c924ad95eeea834deeac67", "scripts/test-audit-public-release.sh", "ssid"],
    ["ed3d0a9967e58535b121e2ab881d2dbb25f44a9e", "scripts/test-audit-public-release.sh", "device-identifier"],
    ["ed3d0a9967e58535b121e2ab881d2dbb25f44a9e", "scripts/test-audit-public-release.sh", "ip-host"],
    ["ed3d0a9967e58535b121e2ab881d2dbb25f44a9e", "scripts/test-audit-public-release.sh", "ssid"],
  ]).freeze
  SAFE_VALUE_WORDS = /(?:\A|[^a-z0-9])(?:demo|example|fake|fixture|mock|placeholder|redacted|sample|synthetic|test(?:ing)?)(?:\z|[^a-z0-9])/i
  SAFE_CONTEXT_WORDS = /(?:\b(?:documentation[- ]only|e\.g\.|example data|for example|mock fixture|redacted fixture|synthetic(?: data| fixture| value)?|test fixture)\b|예시?\s*[:：]?)/i
  SAFE_GENERIC_VALUES = /\A(?:bssid|current location|device|device id|location|network|serial number|ssid|wi-?fi(?: network)?)\z/i
  BINARY_IP_LABEL = /\b(?:address|gateway|host|ip(?:v[46])?(?:[ _-]?address)?|router|server)\s*(?::|=|\bis\b)/i

  DOCUMENTATION_V4 = %w[192.0.2.0/24 198.51.100.0/24 203.0.113.0/24].map { |range| IPAddr.new(range) }.freeze
  DOCUMENTATION_V6 = [IPAddr.new("2001:db8::/32")].freeze
  NON_PERSONAL_V4 = [IPAddr.new("0.0.0.0/32"), IPAddr.new("127.0.0.0/8"), IPAddr.new("255.255.255.255/32")].freeze
  NON_PERSONAL_V6 = [IPAddr.new("::/128"), IPAddr.new("::1/128")].freeze
  STANDARD_NETWORK_LITERALS = Set.new(%w[
    10.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 fc00::/7 fe80::/10
  ]).freeze

  Literal = Struct.new(:value, :quoted, keyword_init: true)
  Finding = Struct.new(:category, :value, keyword_init: true)

  def git_capture(root, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", root, *arguments)
    abort "Public-release privacy scanner could not inspect Git metadata." unless status.success?
    stdout.b
  end

  def git_blob_id(root, bytes)
    stdout, _, status = Open3.capture3(
      "git", "-C", root, "hash-object", "--stdin", stdin_data: bytes
    )
    abort "Public-release privacy scanner could not identify working-tree content." unless status.success?
    stdout.strip
  end

  def reviewed_synthetic_finding?(object, path, category)
    REVIEWED_SYNTHETIC_FINDINGS.include?([object, path, category])
  end

  def each_object_path(output)
    return enum_for(:each_object_path, output) unless block_given?
    pending_object = nil
    output.split("\0").each do |entry|
      object, path = entry.split(" ", 2)
      if object&.match?(/\A[0-9a-f]{40,64}\z/)
        pending_object = object
        if path
          yield object, path
          pending_object = nil
        end
      elsif pending_object && entry.start_with?("path=")
        path = entry.byteslice(5, entry.bytesize - 5)
        yield pending_object, path if path
        pending_object = nil
      end
    end
  end

  def relevant_path?(path)
    return false if path.empty? || SKIPPED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    basename = File.basename(path)
    extension = File.extname(basename).downcase
    TEXT_EXTENSIONS.include?(extension) || ASSET_EXTENSIONS.include?(extension) ||
      EXTENSIONLESS_TEXT.include?(basename)
  end

  def binary_asset?(path)
    extension = File.extname(path).downcase
    ASSET_EXTENSIONS.include?(extension) && !TEXT_EXTENSIONS.include?(extension)
  end

  def text_content(path, bytes)
    if binary_asset?(path)
      bytes.scan(/[\x20-\x7e]{4,}/n).join("\n").force_encoding(Encoding::UTF_8)
    else
      bytes.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end

  def inside_quoted_text?(prefix)
    unescaped = prefix.gsub(/\\["\x27]/, "")
    unescaped.count(%q{"}).odd? || unescaped.count(39.chr).odd?
  end

  def captures_to_literal(match)
    value = match[:double_quoted] || match[:single_quoted] || match[:bare]
    return nil unless value
    Literal.new(
      value: value.to_s.strip,
      quoted: !match[:double_quoted].nil? || !match[:single_quoted].nil?
    )
  end

  def literal_values(line, label_pattern, numeric_only: false, binary_metadata: false)
    value_pattern = if numeric_only
      %q{(?:"(?<double_quoted>[-+]?\d{1,3}(?:\.\d{3,})?)"|\x27(?<single_quoted>[-+]?\d{1,3}(?:\.\d{3,})?)\x27|(?<bare>[-+]?\d{1,3}(?:\.\d{3,})?))}
    else
      %q{(?:"(?<double_quoted>[^"\r\n]{1,160})"|\x27(?<single_quoted>[^\x27\r\n]{1,160})\x27|(?<bare>[A-Za-z0-9][A-Za-z0-9._:@+%/-]{0,159}))}
    end
    patterns = [
      Regexp.new(%Q!(?:\\A\\s*(?:[-*]\\s*)?(?:\\{\\s*)?|[,\\{]\\s*)["\\x27](?:#{label_pattern})["\\x27]\\s*(?::|=)\\s*#{value_pattern}!, Regexp::IGNORECASE),
      Regexp.new(%Q!(?:\\A\\s*(?:[-*]\\s*)?(?:export\\s+)?|[,(\\{]\\s*)(?:#{label_pattern})\\s*(?::|=)\\s*#{value_pattern}!, Regexp::IGNORECASE)
    ]
    if binary_metadata
      patterns << Regexp.new(
        %Q!(?:\\A|[\\s;,])(?:#{label_pattern})\\s*(?::|=)\\s*#{value_pattern}!,
        Regexp::IGNORECASE
      )
    end

    literals = []
    patterns.each_with_index do |pattern, pattern_index|
      line.scan(pattern) do
        match = Regexp.last_match
        next if pattern_index == 1 && inside_quoted_text?(line.byteslice(0, match.begin(0)))
        literal = captures_to_literal(match)
        literals << literal if literal
      end
    end
    literals.uniq { |literal| [literal.value, literal.quoted] }
  end

  def xml_literal_values(content, label_pattern, numeric_only: false)
    value_pattern = numeric_only ? %q{[-+]?\d{1,3}(?:\.\d{3,})?} : %q{[^<\r\n]{1,160}}
    pattern = Regexp.new(
      %Q!<key>\\s*(?:#{label_pattern})\\s*</key>\\s*<(?<tag>string|real)>\\s*(?<value>#{value_pattern})\\s*</\\k<tag>>!,
      Regexp::IGNORECASE
    )
    literals = []
    content.scan(pattern) do
      match = Regexp.last_match
      literals << [
        Literal.new(value: match[:value].to_s.strip, quoted: true),
        content.byteslice([match.begin(0) - 240, 0].max, match[0].bytesize + 480).to_s
      ]
    end
    literals
  end

  def safe_literal?(literal, context, path, category)
    value = literal.value
    normalized = value.strip.downcase
    return true if normalized.empty?
    return true if %w[nil none null unknown unavailable omitted].include?(normalized)
    return true if normalized.match?(/\A<[^>]+>\z/) || normalized.match?(SAFE_VALUE_WORDS)
    return true if normalized.match?(SAFE_GENERIC_VALUES)
    return true if normalized.match?(/(?:%@|%\{|\$\{|\\\(|\{\{)/)
    if category == "device-identifier"
      synthetic_device = normalized.match?(
        /\A(?:audio|device|display|input|mock|output|sample|screen|serial|speaker|synthetic|test|uid|usb)(?:[-_.:][a-z0-9]+)+\z/i
      )
      return true if synthetic_device
    end
    if !literal.quoted && SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
      return true unless %w[coordinates ip-host].include?(category)
    end
    context.match?(SAFE_CONTEXT_WORDS)
  end

  def safe_ip?(candidate, context, path)
    return true if STANDARD_NETWORK_LITERALS.include?(candidate.downcase)
    token = candidate.sub(%r{/\d{1,3}\z}, "")
    token = token.sub(/%[A-Za-z0-9_.-]+\z/, "")
    address = IPAddr.new(token)
    return true if candidate.include?("/") && address.to_s.casecmp(token).zero?
    range_address = address.ipv4_mapped? ? address.native : address
    ranges = range_address.ipv4? ? DOCUMENTATION_V4 + NON_PERSONAL_V4 : DOCUMENTATION_V6 + NON_PERSONAL_V6
    return true if ranges.any? { |range| range.include?(range_address) }
    safe_literal?(Literal.new(value: candidate, quoted: false), context, path, "ip-host")
  rescue IPAddr::InvalidAddressError
    true
  end

  def context_for(lines, index)
    lines[[index - 12, 0].max, 25].to_a.join
  end

  def add_literal_findings(findings, literals, category, context, path)
    literals.each do |literal|
      findings << Finding.new(category: category, value: literal.value) unless safe_literal?(literal, context, path, category)
    end
  end

  def scan_content(path, bytes)
    content = text_content(path, bytes)
    lines = content.lines
    findings = []
    binary_metadata = binary_asset?(path)
    localization_resource = File.extname(path).downcase == ".strings"
    has_labeled_data = !localization_resource && content.match?(/(?:bssid|ssid|latitude|longitude|coordinates?|location|device[ _-]?(?:uid|uuid)|serial)/i)
    lines.each_with_index do |line, index|
      context = nil
      if has_labeled_data
        ssid_values = literal_values(
          line,
          %q{(?:wi-?fi[ _-]*)?(?:bssid|ssid)},
          binary_metadata: binary_metadata
        )
        unless ssid_values.empty?
          context ||= context_for(lines, index)
          add_literal_findings(findings, ssid_values, "ssid", context, path)
        end

        coordinate_values = literal_values(
          line,
          %q{(?:latitude|longitude|coordinates?|geo[ _-]?location)},
          numeric_only: true,
          binary_metadata: binary_metadata
        )
        unless coordinate_values.empty?
          context ||= context_for(lines, index)
          add_literal_findings(findings, coordinate_values, "coordinates", context, path)
        end

        location_values = literal_values(
          line,
          %q{(?:exact[ _-]?)?location},
          binary_metadata: binary_metadata
        )
        unless location_values.empty?
          context ||= context_for(lines, index)
          add_literal_findings(findings, location_values, "location", context, path)
        end

        device_values = literal_values(
          line,
          %q{(?:device[ _-]?(?:uid|uuid)|serial(?:[ _-]?(?:number|no))?)},
          binary_metadata: binary_metadata
        )
        unless device_values.empty?
          context ||= context_for(lines, index)
          add_literal_findings(findings, device_values, "device-identifier", context, path)
        end
      end

      scan_ip_literals = !binary_metadata || line.match?(BINARY_IP_LABEL)
      if scan_ip_literals && line.include?(".")
        line.scan(/(?<![0-9.])(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?(?![0-9.])/).each do |candidate|
          context ||= context_for(lines, index)
          findings << Finding.new(category: "ip-host", value: candidate) unless safe_ip?(candidate, context, path)
        end
      end
      if scan_ip_literals && line.count(":") >= 2
        line.scan(/(?<![0-9A-Za-z])(?:[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]+)(?:%[A-Za-z0-9_.-]+)?(?:\/\d{1,3})?(?![0-9A-Za-z])/).each do |candidate|
          next if candidate.count(":") < 2
          begin
            IPAddr.new(candidate.sub(%r{/\d{1,3}\z}, "").sub(/%[A-Za-z0-9_.-]+\z/, ""))
          rescue IPAddr::InvalidAddressError
            next
          end
          context ||= context_for(lines, index)
          findings << Finding.new(category: "ip-host", value: candidate) unless safe_ip?(candidate, context, path)
        end
      end
    end

    unless binary_metadata || localization_resource
      xml_literal_values(content, %q{(?:wi-?fi[ _-]*)?(?:bssid|ssid)}).each do |literal, context|
        add_literal_findings(findings, [literal], "ssid", context, path)
      end
      xml_literal_values(
        content,
        %q{(?:latitude|longitude|coordinates?|geo[ _-]?location)},
        numeric_only: true
      ).each do |literal, context|
        add_literal_findings(findings, [literal], "coordinates", context, path)
      end
      xml_literal_values(content, %q{(?:exact[ _-]?)?location}).each do |literal, context|
        add_literal_findings(findings, [literal], "location", context, path)
      end
      xml_literal_values(
        content,
        %q{(?:device[ _-]?(?:uid|uuid)|serial(?:[ _-]?(?:number|no))?)}
      ).each do |literal, context|
        add_literal_findings(findings, [literal], "device-identifier", context, path)
      end
    end

    findings.uniq { |finding| [finding.category, finding.value] }
  end

  def report_path(path, finding)
    raw_path = path.b
    raw_value = finding.value.to_s.b
    display_path = raw_path.dup.force_encoding(Encoding::UTF_8)
    safe_characters = display_path.valid_encoding? && display_path.match?(/\A[A-Za-z0-9._\/@+ -]+\z/)
    value_in_path = !raw_value.empty? && raw_path.downcase.include?(raw_value.downcase)
    return display_path if safe_characters && !value_in_path
    "path-digest-#{Digest::SHA256.hexdigest(raw_path)[0, 16]}"
  end

  records = []
  tracked_paths = git_capture(root, "ls-files", "-z").split("\0").map(&:to_s)
  tracked_paths.select { |path| relevant_path?(path) }.sort.each do |path|
    absolute_path = File.join(root, path)
    unless File.file?(absolute_path) && !File.symlink?(absolute_path)
      raise "Public-release privacy scanner found an unsupported tracked entry."
    end
    bytes = File.binread(absolute_path)
    findings = scan_content(path, bytes)
    object = git_blob_id(root, bytes) unless findings.empty?
    findings.each do |finding|
      next if reviewed_synthetic_finding?(object, path, finding.category)
      records << ["WORKTREE", report_path(path, finding), finding.category]
    end
  end

  paths_by_object = Hash.new { |hash, key| hash[key] = Set.new }
  each_object_path(git_capture(root, "rev-list", "--objects", "--all", "-z")) do |object, path|
    paths_by_object[object] << path if relevant_path?(path)
  end

  unless paths_by_object.empty?
    Open3.popen3("git", "-C", root, "cat-file", "--batch") do |stdin, stdout, stderr, wait_thread|
      paths_by_object.each_key { |object| stdin.puts(object) }
      stdin.close
      paths_by_object.each do |object, paths|
        header = stdout.gets
        abort "Public-release privacy scanner received malformed Git object metadata." unless header
        returned_object, type, size_text = header.chomp.split(" ", 3)
        abort "Public-release privacy scanner received the wrong Git object." unless returned_object == object
        size = Integer(size_text, 10)
        bytes = stdout.read(size)
        separator = stdout.read(1)
        abort "Public-release privacy scanner received a truncated Git object." unless bytes&.bytesize == size && separator == "\n"
        next unless type == "blob"
        paths.sort.each do |path|
          scan_content(path, bytes).each do |finding|
            next if reviewed_synthetic_finding?(object, path, finding.category)
            records << ["HISTORY", object, report_path(path, finding), finding.category]
          end
        end
      end
      error_text = stderr.read
      abort "Public-release privacy scanner could not read Git objects." unless wait_thread.value.success? && error_text.empty?
    end
  end

  message_objects = {}
  git_capture(root, "rev-list", "--all").each_line do |line|
    object = line.strip
    message_objects[object] = "COMMIT_MESSAGE" if object.match?(/\A[0-9a-f]{40,64}\z/)
  end
  git_capture(
    root,
    "for-each-ref",
    "--format=%(objecttype) %(objectname)",
    "refs/tags"
  ).each_line do |line|
    object_type, object = line.strip.split(" ", 2)
    if object_type == "tag" && object&.match?(/\A[0-9a-f]{40,64}\z/)
      message_objects[object] = "TAG_MESSAGE"
    end
  end

  unless message_objects.empty?
    Open3.popen3("git", "-C", root, "cat-file", "--batch") do |stdin, stdout, stderr, wait_thread|
      message_objects.each_key { |object| stdin.puts(object) }
      stdin.close
      message_objects.each do |object, scope|
        header = stdout.gets
        abort "Public-release privacy scanner received malformed Git message metadata." unless header
        returned_object, type, size_text = header.chomp.split(" ", 3)
        abort "Public-release privacy scanner received the wrong Git message object." unless returned_object == object
        size = Integer(size_text, 10)
        bytes = stdout.read(size)
        separator = stdout.read(1)
        abort "Public-release privacy scanner received a truncated Git message object." unless bytes&.bytesize == size && separator == "\n"
        expected_type = scope == "COMMIT_MESSAGE" ? "commit" : "tag"
        next unless type == expected_type
        body_offset = bytes.index("\n\n".b)
        next unless body_offset
        body_offset += 2
        body = bytes.byteslice(body_offset, bytes.bytesize - body_offset)
        scan_content("git-message.txt", body).each do |finding|
          records << [scope, object, finding.category]
        end
      end
      error_text = stderr.read
      abort "Public-release privacy scanner could not read Git messages." unless wait_thread.value.success? && error_text.empty?
    end
  end

  File.open(output_path, "wb", 0o600) do |output|
    records.uniq.sort.each { |record| output.puts(record.join(":")) }
  end
  rescue StandardError
    exit 2
  end
' "$ROOT_DIR" "$privacy_hits"; then
    echo "Public-release privacy scanner failed closed." >&2
    exit 1
fi

placeholder_pattern='TBD''_FINAL_[A-Z0-9_]+|COMMIT''_PENDING|CHANGE''ME'
capture_git_grep "$git_scan_output" -I -n -E "$placeholder_pattern" -- \
    ':!Tests/**' ':!docs/evidence/**'
if [[ -s "$git_scan_output" ]]; then
    echo "Unresolved public-release placeholder found in the current tree." >&2
    exit 1
fi

if [[ -s "$secret_hits" ]]; then
    echo "Potential credential pattern found in Git history (values suppressed):" >&2
    render_opaque_finding_metadata <"$secret_hits" >&2
    exit 1
fi

if [[ -s "$home_path_hits" ]]; then
    echo "Concrete personal home path found in Git history (values suppressed):" >&2
    render_opaque_finding_metadata <"$home_path_hits" >&2
    exit 1
fi

if [[ -s "$image_hits" ]]; then
    echo "Potential secret or personal path found in tracked or historical image metadata (values suppressed):" >&2
    render_opaque_finding_metadata <"$image_hits" >&2
    exit 1
fi

if [[ -s "$privacy_hits" ]]; then
    echo "Potential private device, network, or location data found (values suppressed):" >&2
    sort -u "$privacy_hits" >&2
    exit 1
fi

echo "Public-release history, privacy, and asset metadata audit passed."
