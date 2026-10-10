# Consuming coil-regex

Package name is `regex`. Put this package's `src/` on `[module] roots` and `use regex::{…}` resolves here. `extern "libpcre2-8.so.0"` in `src/regex.hy` loads the system libpcre2-8 (dload stem `pcre2-8`; `libpcre2-8.dylib` on macOS). Application code does not call `dload`.

Spool will own Coil-to-Coil deps once a public CLI can resolve git tags ([COI-219](https://linear.app/ardax/issue/COI-219)). Until then `{ git }` parses and the pin is `coil.lock`.

## Sibling checkout

This is the working path. Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-regex/src"]
```

`[dependencies] regex = { path = "../coil-regex" }` is optional spool metadata. The compiler does not follow path deps for discovery. `roots` is what loads `src/regex.hy`.

Install libpcre2-8 (`libpcre2-8-0` / `libpcre2-dev` on Debian/Ubuntu, `pcre2` on Homebrew). Nothing to build here. Grant and pin the library when you run:

```bash
lib=$(pkg-config --variable=libdir libpcre2-8)/libpcre2-8.so.0   # libpcre2-8.dylib on macOS
coil --allow-dload pcre2-8 --dload-pin pcre2-8=$(sha256sum "$lib" | cut -d' ' -f1) \
     --ffi-search-path "$(dirname "$lib")" main.hy
```

The pin is checked against the file found on `--ffi-search-path`. `--dload-trusted pcre2-8` instead of the pin lets dload use the system loader's own search, unhashed.

Then:

```coil
use regex::{compile, find_all, Regex};

let re = compile("(\\w+)=(\\d+)", "i")?;
```

Function list, flags, and errors are in [api.md](api.md).

## Git dep and coil.lock

`{ git }` is the parseable form. `version` and `rev` are optional schema, stored only. They are not a resolved tag. Do not run `spool add`. There is no public spool CLI.

Parseable example:

```toml
[dependencies]
regex = { git = "https://github.com/ardax-corp/coil-regex.git" }

[module]
roots = ["./src", "./.spool/deps/regex/src"]
```

This repo has no tags until [COI-219](https://linear.app/ardax/issue/COI-219). The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`.

`coil.lock`:

```
# spool lockfile v1
[[package]]
name = 'regex'
git = 'https://github.com/ardax-corp/coil-regex.git'
rev = '<commit SHA>'
content_hash = '<tree SHA>'
```

`rev` is the commit. `content_hash` is that commit's git tree. After checkout:

```bash
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
```

The compiler does not read `coil.lock`. Check out that `rev` and point `[module] roots` at its `src/`.

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
