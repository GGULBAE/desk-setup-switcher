.PHONY: build test lint analyze audit-public-release verify-public-assets verify-public-surface package verify-package \
	test-release-tooling release-preflight release-candidate verify-release-candidate \
	verify-downloaded-release verify-remote-controls verify-remote-controls-predecessor-pre-tag \
	verify-remote-controls-final-pre-tag verify-remote-controls-pre-publication \
	plan-legacy-workflow-containment \
	apply-legacy-workflow-containment verify clean

build:
	./scripts/build.sh

test:
	./scripts/test.sh

lint:
	./scripts/lint.sh

analyze:
	./scripts/analyze.sh

audit-public-release:
	./scripts/test-audit-public-release.sh
	./scripts/audit-public-release.sh

verify-public-assets:
	./scripts/verify-public-assets.sh

verify-public-surface:
	./scripts/verify-public-surface.sh

package:
	./scripts/package.sh

verify-package:
	./scripts/verify-package.sh

test-release-tooling:
	./scripts/release/test-release-tooling.sh

release-preflight:
	./scripts/release/preflight.sh

release-candidate:
	./scripts/release/build-candidate.sh

verify-release-candidate:
	./scripts/release/verify-candidate.sh "$(RELEASE_SOURCE_DIR)"

verify-downloaded-release:
	./scripts/release/verify-downloaded-candidate.sh

verify-remote-controls: verify-remote-controls-predecessor-pre-tag

verify-remote-controls-predecessor-pre-tag:
	@test -n "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT:-}" || { \
		echo 'REMOTE_CONTROLS_EVIDENCE_OUTPUT must be an absent absolute path in an owner-0700 directory outside the repository.' >&2; \
		exit 2; \
	}
	@./scripts/release/verify-remote-controls.sh --phase predecessor-pre-tag \
		--evidence-output "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT}"

verify-remote-controls-final-pre-tag:
	@test -n "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT:-}" || { \
		echo 'REMOTE_CONTROLS_EVIDENCE_OUTPUT must be an absent absolute path in an owner-0700 directory outside the repository.' >&2; \
		exit 2; \
	}
	@test -n "$${PREDECESSOR_COMMIT:-}" || { echo 'PREDECESSOR_COMMIT is required.' >&2; exit 2; }
	@test -n "$${PREDECESSOR_TAG_OBJECT:-}" || { echo 'PREDECESSOR_TAG_OBJECT is required.' >&2; exit 2; }
	@./scripts/release/verify-remote-controls.sh --phase final-pre-tag \
		--predecessor-commit "$${PREDECESSOR_COMMIT}" \
		--predecessor-tag-object "$${PREDECESSOR_TAG_OBJECT}" \
		--evidence-output "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT}"

verify-remote-controls-pre-publication:
	@test -n "$${PREDECESSOR_COMMIT:-}" || { echo 'PREDECESSOR_COMMIT is required.' >&2; exit 2; }
	@test -n "$${PREDECESSOR_TAG_OBJECT:-}" || { echo 'PREDECESSOR_TAG_OBJECT is required.' >&2; exit 2; }
	@test -n "$${RELEASE_COMMIT:-}" || { echo 'RELEASE_COMMIT is required.' >&2; exit 2; }
	@test -n "$${RELEASE_TAG_OBJECT:-}" || { echo 'RELEASE_TAG_OBJECT is required.' >&2; exit 2; }
	@test -n "$${RELEASE_ID:-}" || { echo 'RELEASE_ID is required.' >&2; exit 2; }
	@./scripts/release/verify-remote-controls.sh --phase pre-publication \
		--predecessor-commit "$${PREDECESSOR_COMMIT}" \
		--predecessor-tag-object "$${PREDECESSOR_TAG_OBJECT}" \
		--release-commit "$${RELEASE_COMMIT}" \
		--release-tag-object "$${RELEASE_TAG_OBJECT}" \
		--release-id "$${RELEASE_ID}"

plan-legacy-workflow-containment:
	@test -n "$${EXPECTED_MASTER_SHA:-}" || { \
		echo 'EXPECTED_MASTER_SHA is required.' >&2; \
		exit 2; \
	}
	@test -n "$${CONTAINMENT_PLAN_RECEIPT:-}" || { \
		echo 'CONTAINMENT_PLAN_RECEIPT is required.' >&2; \
		exit 2; \
	}
	@./scripts/release/contain-legacy-release-workflow.sh plan \
		--expected-master "$${EXPECTED_MASTER_SHA}" \
		--receipt-output "$${CONTAINMENT_PLAN_RECEIPT}"

apply-legacy-workflow-containment:
	@test -n "$${EXPECTED_MASTER_SHA:-}" || { \
		echo 'EXPECTED_MASTER_SHA is required.' >&2; \
		exit 2; \
	}
	@test -n "$${CONTAINMENT_PLAN_RECEIPT:-}" || { \
		echo 'CONTAINMENT_PLAN_RECEIPT is required.' >&2; \
		exit 2; \
	}
	@test -n "$${CONTAINMENT_PLAN_DIGEST:-}" || { \
		echo 'CONTAINMENT_PLAN_DIGEST is required.' >&2; \
		exit 2; \
	}
	@test -n "$${CONTAINMENT_RESULT_RECEIPT:-}" || { \
		echo 'CONTAINMENT_RESULT_RECEIPT is required.' >&2; \
		exit 2; \
	}
	@./scripts/release/contain-legacy-release-workflow.sh apply \
		--expected-master "$${EXPECTED_MASTER_SHA}" \
		--plan-receipt "$${CONTAINMENT_PLAN_RECEIPT}" \
		--plan-digest "$${CONTAINMENT_PLAN_DIGEST}" \
		--receipt-output "$${CONTAINMENT_RESULT_RECEIPT}"

verify:
	./scripts/verify.sh

clean:
	./scripts/clean.sh
