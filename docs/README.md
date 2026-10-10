# coil-regex

PCRE2-backed regular expressions for coil. `src/regex.hy` binds libpcre2-8 directly with `extern`; there is no C shim.

## Package layout

| Path | Role |
|------|------|
| `src/regex.hy` | `Regex` class, `RegexError`, free functions |
| `tests/regex.hy` | `coil test` suite |
| `examples/regex_demo.hy` | End-to-end demo |

## Test

From this directory (with `coil` on `PATH` or via `cargo run --bin coil` from coil-lang):

```bash
make test
```

`make test` finds libpcre2-8 with `pkg-config` (override with `PCRE2_LIBDIR=…`) and passes its SHA-256 to `--dload-pin pcre2-8=…`.

## See also

- [api.md](api.md) — function reference
- [consume.md](consume.md). Sibling checkout, `{ git }`, `coil.lock` `rev` + `content_hash`, dload flags
