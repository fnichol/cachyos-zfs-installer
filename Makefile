SH_TESTS := $(shell find tests -type f -name '*_test.sh')

include vendor/mk/base.mk
include vendor/mk/libsh-vendor.mk
include vendor/mk/shell.mk

SH_SOURCES += ./bin/install
SH_SOURCES += ./src/pacman-zfs/usr/local/bin/pacman-zfs-pre
SH_SOURCES += ./src/pacman-zfs/usr/local/bin/pacman-zfs-post

build:
.PHONY: build

test: test-shell ## Runs all tests
.PHONY: test

check: check-shell ## Checks all linting, styling, & other rules
.PHONY: check

clean: clean-shell ## Cleans up project
.PHONY: clean
