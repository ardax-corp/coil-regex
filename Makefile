# coil-regex: run package tests against the system libpcre2-8.
#
# Targets:
#   make test  — coil language harness (needs `coil` on PATH and libpcre2-8)
#
# The package binds libpcre2-8 directly (no C shim). coil's dload gate needs
# `--dload-pin pcre2-8=SHA256` (or `--dload-trusted pcre2-8`) for that library.

.PHONY: all test print-lib

COIL ?= coil

# Directory holding libpcre2-8 (override if pkg-config is missing).
PCRE2_LIBDIR ?= $(shell pkg-config --variable=libdir libpcre2-8 2>/dev/null)

# The file dload opens for `libpcre2-8.so.0` on this platform.
PCRE2_LIB ?= $(firstword $(wildcard \
	$(PCRE2_LIBDIR)/libpcre2-8.so.0 \
	$(PCRE2_LIBDIR)/libpcre2-8.dylib))

sha256 = $(shell if command -v sha256sum >/dev/null 2>&1; then sha256sum "$(1)"; \
	else shasum -a 256 "$(1)"; fi 2>/dev/null | awk '{print $$1}')

all: test

print-lib:
	@echo $(PCRE2_LIB)

test:
	@test -n "$(PCRE2_LIB)" || { echo "libpcre2-8 not found; set PCRE2_LIBDIR" >&2; exit 1; }
	$(COIL) test --allow-dload pcre2-8 --dload-pin pcre2-8=$(call sha256,$(PCRE2_LIB)) \
		--ffi-search-path $(dir $(PCRE2_LIB))
