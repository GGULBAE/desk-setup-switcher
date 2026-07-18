.PHONY: build test lint analyze audit-public-release package verify-package verify clean

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

package:
	./scripts/package.sh

verify-package:
	./scripts/verify-package.sh

verify:
	./scripts/verify.sh

clean:
	./scripts/clean.sh
