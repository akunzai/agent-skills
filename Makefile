.PHONY: test lint lint-shell

SHELL_FILES := $(shell find tests skills plugins -name '*.sh' -type f 2>/dev/null)

test:
	@exit_code=0; \
	for t in tests/*.sh; do \
		if bash "$$t"; then \
			printf 'PASS: %s\n' "$$t"; \
		else \
			printf 'FAIL: %s\n' "$$t"; \
			exit_code=1; \
		fi; \
	done; \
	exit $$exit_code

lint: lint-shell

lint-shell:
	@echo "Running shellcheck..."
	@shellcheck $(SHELL_FILES)
