# Build libregex for coil-regex FFI.
# Requires libpcre2-8 (pkg-config libpcre2-8, or -lpcre2-8).

ARTIFACT_DIR ?= .

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
PCRE2_CFLAGS ?= $(shell pkg-config --cflags libpcre2-8 2>/dev/null)
PCRE2_LIBS ?= $(shell pkg-config --libs libpcre2-8 2>/dev/null)
ifeq ($(PCRE2_LIBS),)
  PCRE2_LIBS := -lpcre2-8
endif

UNAME_S := $(shell uname -s 2>/dev/null)

# MSYS2/MINGW sets MSYSTEM; plain Windows_NT without a Unix shell is unsupported here.
ifdef MSYSTEM
  PLATFORM := windows
else ifeq ($(OS),Windows_NT)
  PLATFORM := windows
else ifeq ($(UNAME_S),Darwin)
  PLATFORM := macos
else
  PLATFORM := linux
  ifneq ($(shell $(CC) -dumpmachine 2>/dev/null | grep -o musl),)
    PLATFORM := linux-musl
  endif
endif

ifeq ($(PLATFORM),macos)
  LIB := libregex.dylib
  LDFLAGS_SHLIB := -dynamiclib
  SMOKE_RPATH :=
else ifeq ($(PLATFORM),windows)
  LIB := libregex.dll
  LDFLAGS_SHLIB := -shared
  SMOKE_RPATH :=
else
  LIB := libregex.so
  LDFLAGS_SHLIB := -shared -fPIC
  SMOKE_RPATH := -Wl,-rpath,'$$ORIGIN'
endif

LIB_PATH := $(ARTIFACT_DIR)/$(LIB)

.PHONY: all artifact clean smoke print-artifact print-platform

all: artifact

artifact: $(LIB_PATH)

print-platform:
	@echo $(PLATFORM)

print-artifact:
	@echo $(LIB_PATH)

regex.o: regex.c regex.h
	$(CC) $(CFLAGS) $(PCRE2_CFLAGS) -c -o $@ regex.c

$(LIB_PATH): regex.o
	$(CC) $(LDFLAGS_SHLIB) -o $@ $^ $(PCRE2_LIBS)

smoke.bin: smoke.c regex.h $(LIB_PATH)
	$(CC) $(CFLAGS) $(PCRE2_CFLAGS) -o $@ smoke.c -L$(ARTIFACT_DIR) -lregex $(PCRE2_LIBS) $(SMOKE_RPATH)

smoke: smoke.bin
	./smoke.bin

clean:
	rm -f regex.o smoke.bin smoke \
		$(ARTIFACT_DIR)/libregex.so \
		$(ARTIFACT_DIR)/libregex.dylib \
		$(ARTIFACT_DIR)/libregex.dll \
		$(ARTIFACT_DIR)/regex.dll
