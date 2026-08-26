# Consuming coil-regex

Package name is `regex`. Put this package's `src/` on `[module] roots` and `use regex::{…}` resolves here. `extern "regex"` in `src/regex.hy` already loads the native library with `dload("regex")`. Application code does not call `dload`.

Spool will own Coil-to-Coil deps once a public CLI can resolve git tags ([COI-219](https://linear.app/ardax/issue/COI-219)). Native `.so` / `.dylib` / `.dll` stay on `[ffi] search_paths` until [COI-60](https://linear.app/ardax/issue/COI-60).

## Sibling checkout

This is the working path. Clone this repo next to your project. In the consumer `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-regex/src"]

[ffi]
search_paths = ["../coil-regex/native"]
```

`[dependencies] regex = { path = "../coil-regex" }` is optional spool metadata. The compiler does not follow path deps for discovery. `roots` is what loads `src/regex.hy`.

Build the native library from this package root (needs libpcre2-8 and libffi):

```bash
make
# or: make -C native
```

That writes `native/libregex.so` (`.dylib` / `.dll` on other platforms). `dload("regex")` finds it on `search_paths`.

Then:

```coil
use regex::{compile, find_all, Regex};

let re = compile("(\\w+)=(\\d+)", "i")?;
```

Function list, flags, and errors are in [api.md](api.md).

## Git dep and coil.lock

A git dep in `coil.toml` still needs `{ git, version }` or coil reports E0900. `version` is a parser field so the manifest parses. It is not a git tag. Git-only `{ git }` is [COI-220](https://linear.app/ardax/issue/COI-220).

Parseable example:

```toml
[dependencies]
regex = { git = "https://github.com/ardax-corp/coil-regex.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/regex/src"]

[ffi]
search_paths = ["./.spool/deps/regex/native"]
```

There is no public `spool` CLI. This repo has no tags until [COI-219](https://linear.app/ardax/issue/COI-219). The pin is `coil.lock` `rev` + `content_hash`. Omit `tag`. Use sibling checkout until spool materializes `.spool/deps`.

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

The compiler does not read `coil.lock`. Check out that `rev` and point `[module] roots` at its `src/`. Native libs stay on `[ffi] search_paths` until [COI-60](https://linear.app/ardax/issue/COI-60).

## Lifecycle

- Prefer `let re = compile(pat, flags)?;` so `Regex` is dropped when the binding goes out of scope.
- `fn drop()` on `Regex` frees the PCRE2 code. After drop the handle must not be used.
- For long-lived regexes, pin with `gc::root` only if you understand GC ordering. A normal `let` is enough for most code.

## Migrating from virtual `regex`

| Before (coil-lang builtin) | After (coil-regex) |
|----------------------------|---------------------|
| `use regex::{compile, …}` | Same import after adding roots + FFI path |
| `Regex` host handle | `class Regex` with `drop` |
| `RegexError` builtin enum | Userland `enum RegexError` in this package |

No coil `ARCHIVE_VERSION` change is required on the consumer.
