# API

Module: `use regex::{…};` (package name `regex` from `coil.toml`).

## Types

```coil
enum RegexError { Compile, Runtime, NoMatch, Utf8 }

class Regex { pcre2: Pcre2, code: int, match_data: int, count: int }
```

`code` and `match_data` are PCRE2 pointers cast to `int`. A `Regex` keeps its last match, so it is **not** thread-sendable; use one `Regex` per thread.

`Regex` frees both from inherent `fn drop()` at GC / teardown.

Spans start where the match began (`pcre2_get_startchar`) and run for the length of group 0. A pattern using `\K` therefore reports the span from before the `\K`.

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

## PCRE2 binding (FFI)

`regex.hy` binds libpcre2-8 directly: an `extern "libpcre2-8.so.0" { … }` block for plain calls, and a private `Pcre2` class (`declare` / `invoke`) for the calls that write through out-parameters. The unsuffixed `pcre2_*` wrappers are package-internal. Use `Regex` and the free functions from coil source.
