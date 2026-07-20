# uvdesk-docker developer tasks
# Usage: make lint | make test | make check

SHELL := /bin/bash
SCRIPTS := $(shell find scripts -name '*.sh' 2>/dev/null)

.PHONY: help lint test check smoke

help:
	@echo "Targets:"
	@echo "  lint   - ShellCheck over scripts/**"
	@echo "  test   - bats unit tests under tests/"
	@echo "  check  - lint + test"
	@echo "  smoke  - run the image smoke test (requires a built image; see tests/smoke/run-image.sh)"

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "ERROR: shellcheck not installed"; exit 1; }
	@echo "==> ShellCheck"
	@shellcheck -x $(SCRIPTS)
	@echo "OK"

test:
	@command -v bats >/dev/null 2>&1 || { echo "ERROR: bats not installed"; exit 1; }
	@echo "==> bats"
	@bats tests/

check: lint test

smoke:
	@echo "Run: IMAGE_REF=<ref> PLATFORMS='linux/amd64 linux/arm64' tests/smoke/run-image.sh"
	@echo "(builds/pulls the image and asserts installer + DB provisioning per arch)"
