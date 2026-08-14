# API

Module: `use regex::{…};` (package name `regex` from `coil.toml`).

## Types

```coil
enum RegexError { Compile, Runtime, NoMatch, Utf8 }

class Regex { handle: int }
```

Handles are opaque native pointers cast to `int`. They are **not** thread-sendable; use one `Regex` per thread.

`Regex` runs `coil_regex_free` from inherent `fn drop()` at GC / teardown.

## Flags

Second argument to `compile(pattern, flags)` — letters from `i m s x u` (UTF-8 always on):

| Flag | Meaning |
|------|---------|
| `i` | Caseless |
| `m` | Multiline (`^` / `$` per line) |
| `s` | Dot matches newline |
| `x` | Extended (ignore whitespace in pattern) |
| `u` | Unicode properties (UCP) |

Invalid flag letters → `RegexError::Compile`.

## Functions

All return `Result<_, RegexError>` unless noted.

| Function | Description |
|----------|-------------|
| `compile(pattern, flags)` | Build `Regex` |
| `is_match(re, subject)` | Whole-string match test |
| `find(re, subject)` | First match as `(start, end)` **byte** indices |
| `find_all(re, subject)` | All non-overlapping matches; empty vec if none |
| `captures(re, subject)` | Capture groups for first match |
| `captures_all(re, subject)` | Capture rows for every match |
| `split(re, subject)` | Split on matches (trailing segment kept) |
| `replace(re, subject, template)` | Replace first match; `$n`, `${name}`, `$$` |
| `replace_all(re, subject, template)` | Replace all matches |

`find` / `find_all` spans are **byte offsets** into the UTF-8 subject, not Unicode code points.

## Replacement templates

- `$0` … `$9` — numeric capture index
- `${name}` — named capture (PCRE2)
- `$$` — literal `$`

## Errors

| Variant | When |
|---------|------|
| `Compile` | Bad pattern or flags |
| `Runtime` | PCRE2 runtime failure / internal bounds error |
| `NoMatch` | `find` / `captures` with no match |
| `Utf8` | Invalid UTF-8 when building strings |

`find_all` on no matches returns `Ok([])`, not `NoMatch`.

## C ABI (FFI)

Declared in `extern "regex" { … }` inside `regex.hy`. Do not call `pcre2_*` from coil source.
