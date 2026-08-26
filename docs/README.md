# coil-regex

PCRE2-backed regular expressions for coil via `extern "regex"` and userland `src/regex.hy`.

## Package layout

| Path | Role |
|------|------|
| `src/regex.hy` | `Regex` class, `RegexError`, free functions |
| `native/regex.c` | C ABI over libpcre2-8 → `libregex.so` |
| `tests/regex.hy` | `coil test` suite |
| `examples/regex_demo.hy` | End-to-end demo |

## Build native

```bash
make -C native
```

Produces `native/libregex.so` (`.dylib` / `.dll` on other platforms).

## Test

From this directory (with `coil` on `PATH` or via `cargo run --bin coil` from coil-lang):

```bash
coil test
```

## See also

- [api.md](api.md) — function reference
- [consume.md](consume.md). Sibling checkout, `coil.lock` `rev` + `content_hash`, `[ffi] search_paths`
