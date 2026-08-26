// native/regex.c — PCRE2 shim for coil-regex userland package.

#define PCRE2_CODE_UNIT_WIDTH 8
#define _POSIX_C_SOURCE 200809L
#include <pcre2.h>

#include <stdlib.h>
#include <string.h>

#include "regex.h"

typedef struct {
    pcre2_code *code;
    pcre2_match_data *match_data;
    int32_t capture_count;
    char *last_subject;
} CoilRegex;

static CoilRegex *re_from_handle(int64_t handle) {
    if (handle == 0) {
        return NULL;
    }
    return (CoilRegex *)(intptr_t)handle;
}

static int64_t pack_span(int64_t start, int64_t end) {
    return (start << 32) | (uint32_t)end;
}

static uint32_t parse_flags(const char *flags) {
    uint32_t opts = PCRE2_UTF;
    if (!flags) {
        return opts;
    }
    for (const unsigned char *p = (const unsigned char *)flags; *p; p++) {
        switch (*p) {
        case 'i':
            opts |= PCRE2_CASELESS;
            break;
        case 'm':
            opts |= PCRE2_MULTILINE;
            break;
        case 's':
            opts |= PCRE2_DOTALL;
            break;
        case 'x':
            opts |= PCRE2_EXTENDED;
            break;
        case 'u':
            opts |= PCRE2_UCP;
            break;
        default:
            return 0;
        }
    }
    return opts;
}

static size_t subject_len(const char *subject) {
    return subject ? strlen(subject) : 0;
}

static void set_last_subject(CoilRegex *re, const char *subject) {
    free(re->last_subject);
  re->last_subject = NULL;
    if (!subject) {
        return;
    }
    re->last_subject = strdup(subject);
}

static int run_match(CoilRegex *re, const char *subject, size_t offset, int64_t *packed_out) {
    int rc = pcre2_match(
        re->code,
        (PCRE2_SPTR)subject,
        subject_len(subject),
        offset,
        0,
        re->match_data,
        NULL);
    if (rc == PCRE2_ERROR_NOMATCH) {
        return 0;
    }
    if (rc < 0) {
        return -1;
    }
    re->capture_count = rc;
    set_last_subject(re, subject);
    PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(re->match_data);
    if (packed_out) {
        *packed_out = pack_span((int64_t)ovector[0], (int64_t)ovector[1]);
    }
    return 1;
}

int64_t coil_regex_compile(const char *pattern, const char *flags) {
    if (!pattern) {
        return 0;
    }
    uint32_t opts = parse_flags(flags);
    if (opts == 0) {
        return 0;
    }

    int errorcode = 0;
    PCRE2_SIZE erroffset = 0;
    pcre2_code *code = pcre2_compile(
        (PCRE2_SPTR)pattern,
        PCRE2_ZERO_TERMINATED,
        opts,
        &errorcode,
        &erroffset,
        NULL);
    if (!code) {
        return 0;
    }

    CoilRegex *re = (CoilRegex *)calloc(1, sizeof(CoilRegex));
    if (!re) {
        pcre2_code_free(code);
        return 0;
    }
    re->code = code;
    re->match_data = pcre2_match_data_create_from_pattern(code, NULL);
    if (!re->match_data) {
        pcre2_code_free(code);
        free(re);
        return 0;
    }
    return (int64_t)(intptr_t)re;
}

void coil_regex_free(int64_t handle) {
    CoilRegex *re = re_from_handle(handle);
    if (!re) {
        return;
    }
    if (re->match_data) {
        pcre2_match_data_free(re->match_data);
    }
    if (re->code) {
        pcre2_code_free(re->code);
    }
    free(re->last_subject);
    free(re);
}

int64_t coil_regex_is_match(int64_t handle, const char *subject) {
    CoilRegex *re = re_from_handle(handle);
    if (!re || !subject) {
        return COIL_RE_ERR_RUNTIME;
    }
    int64_t packed = 0;
    int rc = run_match(re, subject, 0, &packed);
    if (rc < 0) {
        return COIL_RE_ERR_RUNTIME;
    }
    if (rc == 0) {
        return 0;
    }
    return 1;
}

int64_t coil_regex_find(int64_t handle, const char *subject) {
    CoilRegex *re = re_from_handle(handle);
    if (!re || !subject) {
        return COIL_RE_ERR_RUNTIME;
    }
    int64_t packed = 0;
    int rc = run_match(re, subject, 0, &packed);
    if (rc < 0) {
        return COIL_RE_ERR_RUNTIME;
    }
    if (rc == 0) {
        return COIL_RE_ERR_NOMATCH;
    }
    return packed;
}

int64_t coil_regex_next_match(int64_t handle, const char *subject, int64_t offset) {
    CoilRegex *re = re_from_handle(handle);
    if (!re || !subject || offset < 0) {
        return COIL_RE_ERR_RUNTIME;
    }
    size_t off = (size_t)offset;
    if (off > subject_len(subject)) {
        return COIL_RE_ERR_NOMATCH;
    }
    int64_t packed = 0;
    int rc = run_match(re, subject, off, &packed);
    if (rc < 0) {
        return COIL_RE_ERR_RUNTIME;
    }
    if (rc == 0) {
        return COIL_RE_ERR_NOMATCH;
    }
    return packed;
}

int64_t coil_regex_capture_count(int64_t handle) {
    CoilRegex *re = re_from_handle(handle);
    if (!re) {
        return COIL_RE_ERR_RUNTIME;
    }
    return (int64_t)re->capture_count;
}

static char *copy_capture_bytes(const char *subject, size_t start, size_t end) {
    if (!subject || end < start) {
        char *empty = (char *)malloc(1);
        if (!empty) {
            return NULL;
        }
        empty[0] = '\0';
        return empty;
    }
    size_t len = end - start;
    char *out = (char *)malloc(len + 1);
    if (!out) {
        return NULL;
    }
    memcpy(out, subject + start, len);
    out[len] = '\0';
    return out;
}

static char *copy_substring(CoilRegex *re, uint32_t index) {
    if (!re->last_subject || index >= (uint32_t)re->capture_count) {
        char *empty = (char *)malloc(1);
        if (!empty) {
            return NULL;
        }
        empty[0] = '\0';
        return empty;
    }
    PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(re->match_data);
    size_t start = ovector[index * 2];
    size_t end = ovector[index * 2 + 1];
    if (end == (PCRE2_SIZE)-1) {
        char *empty = (char *)malloc(1);
        if (!empty) {
            return NULL;
        }
        empty[0] = '\0';
        return empty;
    }
    return copy_capture_bytes(re->last_subject, start, end);
}


char *coil_regex_capture_at(int64_t handle, int64_t index) {
    CoilRegex *re = re_from_handle(handle);
    if (!re || index < 0 || index >= re->capture_count) {
        return NULL;
    }
    return copy_substring(re, (uint32_t)index);
}

char *coil_regex_capture_named(int64_t handle, const char *name) {
    CoilRegex *re = re_from_handle(handle);
    if (!re || !name) {
        return NULL;
    }
    // Copy via last_subject; get_byname would dangle after find returns.
    int n = pcre2_substring_number_from_name(re->code, (PCRE2_SPTR)name);
    if (n == PCRE2_ERROR_NOSUBSTRING || n == PCRE2_ERROR_NOUNIQUESUBSTRING) {
        char *empty = (char *)malloc(1);
        if (!empty) {
            return NULL;
        }
        empty[0] = '\0';
        return empty;
    }
    if (n < 0) {
        return NULL;
    }
    return copy_substring(re, (uint32_t)n);
}

int64_t coil_regex_span_start(int64_t packed) {
    return packed >> 32;
}

int64_t coil_regex_span_end(int64_t packed) {
    return (int32_t)(packed & 0xffffffffu);
}
