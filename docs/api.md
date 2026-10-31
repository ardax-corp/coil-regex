# API

Module: `use regex::{…};` (package name `regex` from `coil.toml`).

## Types

```coil
enum RegexError { Compile, Runtime, Utf8 }

class Regex { … }   // opaque: the compiled PCRE2 code and its match data
```

A `Regex` keeps its last match, so it is **not** thread-sendable; use one `Regex` per thread.

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

Each function is also a `Regex` method of the same name without the `re` argument (`re.find_all(subject)`). All return `Result<_, RegexError>`.

| Function | Description |
|----------|-------------|
| `compile(pattern, flags)` | Build `Regex` |
| `is_match(re, subject)` | Whether `re` matches anywhere in `subject` (anchor with `^…$` for the whole string) |
| `find(re, subject)` | First match as `Some((start, end))` **byte** indices, `None` without a match |
| `find_all(re, subject)` | All non-overlapping matches; empty vec if none |
| `captures(re, subject)` | `Some` capture groups for the first match, `None` without a match |
| `captures_all(re, subject)` | Capture rows for every match |
| `split(re, subject)` | Split on matches (trailing segment kept) |
| `replace(re, subject, template)` | Replace first match; `$n`, `${name}`, `$$` |
| `replace_all(re, subject, template)` | Replace all matches |

`find` / `find_all` spans are **byte offsets** into the UTF-8 subject, not Unicode code points.

`Regex` methods `find_at(subject, from)` (first match at or after byte `from`), `matches_prefix(subject)` / `matches_suffix(subject)` (a match anchored at the start / the end) and `expand_template(template)` (the last match's replacement text) back the `Pattern` instance below.

## String methods (`text::Searchable`)

`Regex` implements coil-stdlib's `text::Pattern`, so the `text::Searchable` methods on `string` take a compiled regex wherever they take a literal:

```coil
use text::{Searchable};
use regex::{compile};

let re = compile("[0-9]+", "")?;
"build 42".contains(re);                   // true
"a1b22c".split(re);                        // ["a", "b", "c"]
"a=1 b=2".replace_all(compile("(\\w)=(\\d)", "")?, "$2:$1"); // "1:a 2:b"
"2026-10-22".starts_with(compile("[0-9]{4}-", "")?);           // true
```

`starts_with` / `ends_with` use PCRE2's `ANCHORED` / `ENDANCHORED`, so `ends_with` finds a match ending at the end even when an earlier match does not (`"xab".ends_with(compile("a|ab", "")?)`). `replace_first` / `replace_all` expand `$n` / `${name}` / `$$` in the replacement. A PCRE2 failure while matching (its match limit, say) panics in these methods; call the `Regex` methods for a `Result`. The package now needs coil-stdlib (`text`) on the module path.

## Replacement templates

- `$0` … `$9` — numeric capture index
- `${name}` — named capture (PCRE2)
- `$$` — literal `$`

## Errors

| Variant | When |
|---------|------|
| `Compile` | Bad pattern or flags |
| `Runtime` | PCRE2 runtime failure / internal bounds error |
| `Utf8` | Invalid UTF-8 when building strings |

No match is not an error: `find` / `find_at` / `captures` return `Ok(None)` and `find_all` returns `Ok([])`.

## PCRE2 binding (FFI)

`regex.hy` binds libpcre2-8 directly: an `extern "libpcre2-8.so.0" { … }` block for plain calls, and a private `Pcre2` class (`declare` / `invoke`) for the calls that write through out-parameters and for `pcre2_match_8`, which takes the subject as `ffi::types::ConstBytes` (the string's bytes are lent in place, not copied) with `PCRE2_NO_UTF_CHECK` (coil strings are valid UTF-8). The unsuffixed `pcre2_*` wrappers are package-internal. Use `Regex` and the free functions from coil source.
