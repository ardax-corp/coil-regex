# Build libregex for coil-regex FFI.
# Requires libpcre2-8 (e.g. libpcre2-dev on Debian, pcre2 on Arch).

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  LIB := libregex.dylib
  LDFLAGS := -dynamiclib
else ifeq ($(OS),Windows_NT)
  LIB := regex.dll
  LDFLAGS := -shared
else
  LIB := libregex.so
  LDFLAGS := -shared -fPIC
endif

CFLAGS ?= -O2 -Wall -Wextra -std=c11

.PHONY: all clean

all: $(LIB)

regex.o: regex.c regex.h
	$(CC) $(CFLAGS) -c -o $@ regex.c

$(LIB): regex.o
	$(CC) $(LDFLAGS) -o $@ regex.o -lpcre2-8

clean:
	rm -f regex.o $(LIB)
