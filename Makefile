.PHONY: build test lint analyze package verify-package verify clean

build:
	./scripts/build.sh

test:
	./scripts/test.sh

lint:
	./scripts/lint.sh

analyze:
	./scripts/analyze.sh

package:
	./scripts/package.sh

verify-package:
	./scripts/verify-package.sh

verify:
	./scripts/verify.sh

clean:
	./scripts/clean.sh
