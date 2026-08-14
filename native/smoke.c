#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "regex.h"

int main(void) {
    int64_t h = coil_regex_compile("(\\w+)=(\\d+)", "i");
    if (!h) {
        fprintf(stderr, "compile failed\n");
        return 1;
    }
  const char *subj = "a=1 b=2";
    int64_t packed = coil_regex_find(h, subj);
    printf("packed=%lld\n", (long long)packed);
    char *c1 = coil_regex_capture_at(h, 1);
    char *c2 = coil_regex_capture_at(h, 2);
    printf("cap1=%s cap2=%s\n", c1 ? c1 : "(null)", c2 ? c2 : "(null)");
    free(c1);
    free(c2);
    coil_regex_free(h);
    return 0;
}
