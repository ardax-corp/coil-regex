# coil-regex

Userland PCRE2 regex for [coil](https://github.com/ardax-corp/coil-lang). Replaces the former virtual `use regex::{…}` module with an FFI package and `Regex` class with `fn drop()`.

## Requirements

- coil-lang with finalizers (inherent `fn drop()`)
- libpcre2-8 (`libpcre2-dev` on Debian/Ubuntu, `pcre2` on Homebrew)
- libffi (for coil FFI)

There is no native shim to build: `src/regex.hy` calls libpcre2-8 directly through `extern`.

## Quick start

```bash
make test     # coil language harness (needs coil on PATH)
```

Run the demo (the library must be granted and pinned, see [consume.md](docs/consume.md)):

```bash
coil --allow-dload pcre2-8 --dload-pin pcre2-8=<sha256> --ffi-search-path <libdir> examples/regex_demo.hy
# true,2,a->1 b->2,a|b|c
```

## Docs

- [API](docs/api.md)
- [Consuming in a project](docs/consume.md)

## License

MIT — see [LICENSE](LICENSE).
