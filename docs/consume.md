# Consuming coil-regex

## Sibling checkout (until spool)

In your project's `coil.toml`:

```toml
[module]
roots = ["./src", "../coil-regex/src"]

[ffi]
search_paths = ["../coil-regex/native"]
```

Build the native library once:

```bash
make -C ../coil-regex/native
```

Then in coil source:

```coil
use regex::{compile, find_all, Regex};
```

## Spool (future)

When published to `ardax-corp/coil-regex`:

```toml
[dependencies]
regex = { git = "https://github.com/ardax-corp/coil-regex.git", version = "^0.1" }

[module]
roots = ["./src", "./.spool/deps/regex/src"]

[ffi]
search_paths = ["./.spool/deps/regex/native"]
```

## Lifecycle

- Prefer `let re = compile(pat, flags)?;` so `Regex` is dropped when the binding goes out of scope.
- `fn drop()` on `Regex` frees the PCRE2 code; after drop the handle must not be used.
- For long-lived regexes, pin with `gc::root` only if you understand GC ordering; normal `let` bindings are enough for most code.

## Migrating from virtual `regex`

| Before (coil-lang builtin) | After (coil-regex) |
|----------------------------|---------------------|
| `use regex::{compile, …}` | Same import after adding roots + FFI path |
| `Regex` host handle | `class Regex` with `drop` |
| `RegexError` builtin enum | Userland `enum RegexError` in this package |

No coil `ARCHIVE_VERSION` change is required on the consumer.
