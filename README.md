# coil-regex

Userland PCRE2 regex for [coil](https://github.com/ardax-corp/coil-lang). Replaces the former virtual `use regex::{…}` module with an FFI package and `Regex` class with `fn drop()`.

## Requirements

- coil-lang with finalizers (inherent `fn drop()`)
- libpcre2-8 (`libpcre2-dev` on Debian/Ubuntu, `pcre2` on Homebrew)
- libffi (for coil FFI)

## Quick start

```bash
make          # native/libregex.{so,dylib,dll}
make smoke    # C ABI smoke (optional)
make test     # coil language harness (needs coil on PATH)
```

Or build only the native tree:

```bash
make -C native
```

Run the demo:

```bash
coil examples/regex_demo.hy
# true,2,a->1 b->2,a|b|c
```

## Docs

- [API](docs/api.md)
- [Consuming in a project](docs/consume.md)

## License

MIT — see [LICENSE](LICENSE).
