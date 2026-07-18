#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"

release_require_single_line RELEASE_TAG
release_require_single_line EXPECTED_COMMIT
release_require_single_line RELEASE_CONFIRMATION

expected_tag="v$VERSION"
[[ "$RELEASE_TAG" == "$expected_tag" ]] || {
    release_die "RELEASE_TAG must exactly match the bundle version ($expected_tag)."
}
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
    release_die "EXPECTED_COMMIT must be a full lowercase 40-character commit SHA."
}
[[ "$RELEASE_CONFIRMATION" == "prepare signed draft $RELEASE_TAG" ]] || {
    release_die "The signed-draft confirmation phrase does not match."
}

head_commit="$(git rev-parse --verify HEAD^{commit})"
[[ "$head_commit" == "$EXPECTED_COMMIT" ]] || {
    release_die "Checked-out HEAD does not match EXPECTED_COMMIT."
}

tag_ref="refs/tags/$RELEASE_TAG"
git show-ref --verify --quiet "$tag_ref" || release_die "Release tag does not exist locally."
tag_commit="$(git rev-parse --verify "$tag_ref^{commit}")"
[[ "$tag_commit" == "$EXPECTED_COMMIT" ]] || {
    release_die "Release tag does not resolve to EXPECTED_COMMIT."
}

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
    release_die "Release source checkout must be clean, including untracked files."
fi

if [[ "${GITHUB_ACTIONS:-}" == true ]] \
    && ! git show-ref --verify --quiet refs/remotes/origin/master; then
    release_die "GitHub release preflight requires the fetched origin/master ref."
fi
if git show-ref --verify --quiet refs/remotes/origin/master; then
    git merge-base --is-ancestor "$EXPECTED_COMMIT" refs/remotes/origin/master || {
        release_die "Release commit is not contained in origin/master."
    }
fi

if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    [[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]] || {
        release_die "GitHub release preflight requires workflow_dispatch."
    }
    [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" == "$RELEASE_TAG" ]] || {
        release_die "The workflow must be dispatched from the exact release tag ref."
    }
    [[ "${GITHUB_SHA:-}" == "$EXPECTED_COMMIT" ]] || {
        release_die "GITHUB_SHA does not match EXPECTED_COMMIT."
    }
    [[ "${GITHUB_REPOSITORY:-}" == GGULBAE/desk-setup-switcher ]] || {
        release_die "Unexpected GitHub repository identity."
    }
fi

printf 'Release preflight passed for %s at %s.\n' "$RELEASE_TAG" "$EXPECTED_COMMIT"
