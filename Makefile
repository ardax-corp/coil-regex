# coil-regex — build the FFI artifact and run package tests.
#
# Targets:
#   make / make native  — build native/libregex.{so,dylib,dll}
#   make smoke          — C ABI smoke test (after native)
#   make test           — coil language harness (needs `coil` on PATH)
#   make clean          — remove build products

.PHONY: all native smoke test clean dist

COIL ?= coil

all: native

native:
	$(MAKE) -C native artifact

smoke: native
	$(MAKE) -C native smoke

test: native
	$(COIL) test

clean:
	$(MAKE) -C native clean

dist: native
	@$(MAKE) -C native print-artifact
