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
	build build-release test test-unit test-integration check-spdx check-dangerous \
	test-policy coverage-report check-tool-versions check-policy-ownership check ci clean

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

build:
	swift build --build-tests $(SWIFT_WARNING_FLAGS) \
		-Xswiftc -F -Xswiftc "$(DEVELOPER_FRAMEWORKS)"

build-release:
	swift build --build-tests $(SWIFT_WARNING_FLAGS) -c release \
		-Xswiftc -enable-testing \
		-Xswiftc -F -Xswiftc "$(DEVELOPER_FRAMEWORKS)"

test: test-unit

test-unit:
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

test-integration:
	./scripts/run-integration-tests.sh

check-spdx:
	./scripts/check-spdx.sh

check-dangerous:
	./scripts/check-dangerous-test-commands.sh

check-tool-versions:
	./scripts/check-tool-versions.sh

check-policy-ownership:
	./scripts/check-policy-ownership.sh

check: format-check lint lint-scripts lint-actions check-spdx check-dangerous check-tool-versions \
	check-policy-ownership build build-release test-unit coverage-report test-policy

ci: check

clean:
	swift package clean
