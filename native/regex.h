// coil-regex C ABI — thin wrapper around libpcre2-8 for coil FFI.
#pragma once

#include <stdint.h>

#define COIL_RE_ERR_COMPILE (-1)
#define COIL_RE_ERR_RUNTIME (-2)
#define COIL_RE_ERR_NOMATCH (-3)
#define COIL_RE_ERR_UTF8 (-4)

int64_t coil_regex_compile(const char *pattern, const char *flags);
void coil_regex_free(int64_t handle);

int64_t coil_regex_is_match(int64_t handle, const char *subject);
int64_t coil_regex_find(int64_t handle, const char *subject);
int64_t coil_regex_next_match(int64_t handle, const char *subject, int64_t offset);

int64_t coil_regex_capture_count(int64_t handle);
char *coil_regex_capture_at(int64_t handle, int64_t index);
char *coil_regex_capture_named(int64_t handle, const char *name);

int64_t coil_regex_span_start(int64_t packed);
int64_t coil_regex_span_end(int64_t packed);
