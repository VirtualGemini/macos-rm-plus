# SPDX-License-Identifier: Apache-2.0

SHELL := /bin/sh

TOOLS_BIN := $(CURDIR)/.build/tools/bin
export PATH := $(TOOLS_BIN):$(PATH)
DEVELOPER_DIR := $(shell xcode-select -p)
DEVELOPER_FRAMEWORKS := $(DEVELOPER_DIR)/Library/Developer/Frameworks
DEVELOPER_LIB := $(DEVELOPER_DIR)/Library/Developer/usr/lib

SWIFT_PATHS := Package.swift Sources TestSupport Tests
SWIFT_WARNING_FLAGS := -Xswiftc -warnings-as-errors

.PHONY: bootstrap hooks-install format format-check lint lint-scripts lint-actions \
	build build-release test test-unit test-integration test-put-back-race \
	test-put-back-race-manual test-put-back-symlink-delay-manual \
	test-put-back-symlink-finalizer-manual check-spdx check-dangerous \
	test-policy coverage-report check-tool-versions check-swift-toolchain \
	check-system-trash-boundary \
	check-policy-ownership check ci clean

bootstrap:
	./scripts/bootstrap.sh

hooks-install:
	./scripts/install-hooks.sh

format:
	swift format format --configuration .swift-format --in-place --recursive $(SWIFT_PATHS)

format-check:
	swift format lint --configuration .swift-format --strict --recursive $(SWIFT_PATHS)

lint:
	./scripts/run-swiftlint.sh

lint-scripts:
	$(TOOLS_BIN)/shellcheck scripts/*.sh scripts/lib/*.sh .githooks/* \
		Tests/DocumentationImpactTests/*.sh Tests/PolicyTests/*.sh

lint-actions:
	$(TOOLS_BIN)/actionlint

build: check-swift-toolchain
	swift build --build-tests $(SWIFT_WARNING_FLAGS) \
		-Xswiftc -F -Xswiftc "$(DEVELOPER_FRAMEWORKS)"

build-release: check-swift-toolchain
	swift build --build-tests $(SWIFT_WARNING_FLAGS) -c release \
		-Xswiftc -enable-testing \
		-Xswiftc -F -Xswiftc "$(DEVELOPER_FRAMEWORKS)"

test: test-unit

test-unit: check-swift-toolchain
	DYLD_FRAMEWORK_PATH="$(DEVELOPER_FRAMEWORKS)" \
		swift test --enable-code-coverage --no-parallel $(SWIFT_WARNING_FLAGS) \
		-Xswiftc -F -Xswiftc "$(DEVELOPER_FRAMEWORKS)" \
		-Xlinker -rpath -Xlinker "$(DEVELOPER_FRAMEWORKS)" \
		-Xlinker -rpath -Xlinker "$(DEVELOPER_LIB)"

coverage-report:
	./scripts/report-coverage.sh

test-policy:
	Tests/DocumentationImpactTests/check-doc-impact-tests.sh
	Tests/PolicyTests/check-breaking-change-approvals-tests.sh
	Tests/PolicyTests/check-policy-ownership-tests.sh
	Tests/PolicyTests/check-policy-changes-tests.sh
	Tests/PolicyTests/check-tool-versions-tests.sh
	Tests/PolicyTests/check-swift-toolchain-tests.sh
	Tests/PolicyTests/check-system-trash-boundary-tests.sh

check-swift-toolchain:
	./scripts/check-swift-toolchain.sh

test-integration:
	./scripts/run-integration-tests.sh

test-put-back-race:
	swift run $(SWIFT_WARNING_FLAGS) rmp-test put-back-race --test-run-id "$(TEST_RUN_ID)"

SETTLE_SECONDS ?= 0

CYCLES ?= 1
FIXTURE ?= file
SYMLINK_FIXTURE ?= symbolic-link

test-put-back-race-manual:
	swift run $(SWIFT_WARNING_FLAGS) rmp-test put-back-race-manual \
		--settle-seconds "$(SETTLE_SECONDS)" --cycles "$(CYCLES)" \
		--fixture "$(FIXTURE)" --test-run-id "$(TEST_RUN_ID)"

test-put-back-symlink-delay-manual:
	swift run $(SWIFT_WARNING_FLAGS) rmp-test put-back-symlink-delay-manual \
		--settle-seconds "$(SETTLE_SECONDS)" --cycles "$(CYCLES)" \
		--fixture "$(SYMLINK_FIXTURE)" --test-run-id "$(TEST_RUN_ID)"

test-put-back-symlink-finalizer-manual:
	swift run $(SWIFT_WARNING_FLAGS) rmp-test put-back-symlink-finalizer-manual \
		--cycles "$(CYCLES)" --fixture "$(SYMLINK_FIXTURE)" \
		--test-run-id "$(TEST_RUN_ID)"

check-spdx:
	./scripts/check-spdx.sh

check-dangerous:
	./scripts/check-dangerous-test-commands.sh

check-tool-versions:
	./scripts/check-tool-versions.sh

check-system-trash-boundary:
	./scripts/check-system-trash-boundary.sh

check-policy-ownership:
	./scripts/check-policy-ownership.sh

check: format-check lint lint-scripts lint-actions check-spdx check-dangerous check-tool-versions \
	check-swift-toolchain check-system-trash-boundary check-policy-ownership build build-release \
	test-unit coverage-report \
	test-policy

ci: check

clean:
	swift package clean
