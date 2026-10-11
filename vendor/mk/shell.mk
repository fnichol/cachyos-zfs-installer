SH_SOURCES ?= $(shell find . -type f -name '*.sh' -not -path './tmp/*' -and -not -path './vendor/*')
SHELL_BIN ?= $(SHELL)
SHUNIT2_VERSION := 2.1.8
CHECK_TOOLS += shellcheck shfmt

$(SH_TESTS): testtools dl-shunit2
	@echo
	@echo "--- $@"
	./$@

test-shell: $(SH_TESTS) ## Runs all shell code tests
.PHONY: test-shell

check-shell: shellcheck shfmt ## Checks linting & styling rules for shell code
.PHONY: check-shell

shellcheck: checktools ## Checks shell code for linting rules
	@echo "--- $@"
	shellcheck --external-sources $(SH_SOURCES)
.PHONY: shellcheck

shfmt: checktools ## Checks shell code for consistent formatting
	@echo "--- $@"
	shfmt -i 2 -ci -bn -d -l $(SH_SOURCES)
.PHONY: shfmt

clean-shell: ## Cleans up shell project
	rm -rf tmp
.PHONY: clean-shell

dl-shunit2: tmp/shunit2 ## Downloads shUnit2
.PHOHY: dl-shunit2

tmp/shunit2: tmp/shunit2-$(SHUNIT2_VERSION)
	@echo "--- $@"
	ln -snf ./shunit2-$(SHUNIT2_VERSION) tmp/shunit2

tmp/shunit2-$(SHUNIT2_VERSION):
	@echo "--- $@"
	mkdir -p $@
	curl -sSfL https://github.com/kward/shunit2/archive/v$(SHUNIT2_VERSION).tar.gz \
		| tar xzf - -C tmp/
