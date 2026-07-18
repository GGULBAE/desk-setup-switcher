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
	./scripts/release/verify-remote-controls.sh

verify:
	./scripts/verify.sh

clean:
	./scripts/clean.sh
