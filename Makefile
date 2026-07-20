.PHONY: build test lint analyze audit-public-release verify-public-assets verify-public-surface package verify-package \
	test-release-tooling release-preflight release-candidate verify-release-candidate \
	verify-downloaded-release verify-remote-controls verify clean

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

verify-remote-controls:
	@test -n "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT:-}" || { \
		echo 'REMOTE_CONTROLS_EVIDENCE_OUTPUT must be an absent absolute path in an owner-0700 directory outside the repository.' >&2; \
		exit 2; \
	}
	@./scripts/release/verify-remote-controls.sh --phase final-pre-tag \
		--evidence-output "$${REMOTE_CONTROLS_EVIDENCE_OUTPUT}"

verify:
	./scripts/verify.sh

clean:
	./scripts/clean.sh
