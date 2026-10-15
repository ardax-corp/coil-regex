# Consuming coil-regex

Package name is `regex`. Put this package's `src/` on `--root` and `use regex::{…}` resolves here. `extern "libpcre2-8.so.0"` in `src/regex.hy` loads the system libpcre2-8 (dload stem `pcre2-8`; `libpcre2-8.dylib` on macOS). Application code does not call `dload`.

## Sibling checkout

Clone this repo next to your project. coil reads no `coil.toml` and no `coil.lock`: pass `--root ../coil-regex/src` so `use regex` loads `src/regex.hy`.

Install libpcre2-8 (`libpcre2-8-0` / `libpcre2-dev` on Debian/Ubuntu, `pcre2` on Homebrew). Nothing to build here. Grant and pin the library when you run:

```bash
lib=$(pkg-config --variable=libdir libpcre2-8)/libpcre2-8.so.0   # libpcre2-8.dylib on macOS
coil --root ../coil-regex/src \
     --allow-dload pcre2-8 --dload-pin pcre2-8=$(sha256sum "$lib" | cut -d' ' -f1) \
     --ffi-search-path "$(dirname "$lib")" main.hy
```

The pin is checked against the file found on `--ffi-search-path`. `--dload-trusted pcre2-8` instead of the pin lets dload use the system loader's own search, unhashed.

Then:

```coil
use regex::{compile, find_all, Regex};

let re = compile("(\\w+)=(\\d+)", "i")?;
```

Function list, flags, and errors are in [api.md](api.md).

## With spool

```bash
spool add regex --git https://github.com/ardax-corp/coil-regex.git --rev <commit SHA>
```

This repo has no tags, so pin a commit with `--rev`. spool records the dep, writes `coil.lock` (`rev` + `content_hash`), links `.spool/deps/regex`, and passes `--root` for it. Grant the system library in the consumer `coil.toml`:

```toml
[ffi]
search_paths = ["/usr/lib/x86_64-linux-gnu"]   # dirname of libpcre2-8.so.0
allow = ["pcre2-8"]
```

and pin it with a native row under the `regex` package in `coil.lock` (spool passes it as `--dload-pin pcre2-8=SHA256`):

```
[[package.native]]
stem = 'pcre2-8'
sha256 = '<sha256 of libpcre2-8.so.0>'
```

## Lifecycle

- Prefer `let re = compile(pat, flags)?;` so `Regex` is dropped when the binding goes out of scope.
- `fn drop()` on `Regex` frees the PCRE2 code and match data. After drop the regex must not be used.
- For long-lived regexes, pin with `gc::root` only if you understand GC ordering. A normal `let` is enough for most code.

## Migrating from virtual `regex`

| Before (coil-lang builtin) | After (coil-regex) |
|----------------------------|---------------------|
| `use regex::{compile, …}` | Same import after adding roots + FFI path |
| `Regex` host handle | `class Regex` with `drop` |
| `RegexError` builtin enum | Userland `enum RegexError` in this package |

No coil `ARCHIVE_VERSION` change is required on the consumer.
