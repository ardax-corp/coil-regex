# coil-regex

PCRE2 regular expressions for [coil](https://github.com/ardax-corp/coil-lang). `compile` a pattern into a `Regex`, then match, find, capture, split and replace with its methods. `Regex` is also a `text::Pattern`, so the coil-stdlib string methods (`contains`, `split`, `replace_all`, ...) take it. The package binds the system libpcre2-8 through FFI; there is nothing to build.

## Requirements

- coil-lang with finalizers (inherent `fn drop()`) and `ffi::types::ConstBytes` (archive minor 37)
- libpcre2-8 (`libpcre2-dev` on Debian/Ubuntu, `pcre2` on Homebrew)
- libffi (for coil FFI)
- [coil-stdlib](https://github.com/ardax-corp/coil-stdlib) on the module path (`text::Pattern`)

There is no native shim to build: `src/regex.hy` calls libpcre2-8 directly through `extern`.

## Example

```coil
use regex::{compile, RegexError};
use text::{Searchable};
use io::sync::{println};

// `?` passes a RegexError up to the caller.
fn swap_pairs(string s) -> Result<string, RegexError> {
    let re = compile("(\\w+)=(\\d+)", "")?;
    return re.replace_all(s, "$2=$1")?;
}

fn main() {
    println(swap_pairs("a=1 b=2").unwrap_or("bad pattern"))?;

    // A compiled regex also works with the `text::Searchable` string methods.
    let digits = compile("[0-9]+", "").ok() ?? panic "bad pattern";
    if "build 42".contains(digits) {
        println("has a number")?;
    }
}
```

```bash
lib=$(pkg-config --variable=libdir libpcre2-8)/libpcre2-8.so.0
coil --root ../coil-regex/src --root ../coil-stdlib/src \
     --allow-dload pcre2-8 --dload-pin pcre2-8=$(sha256sum "$lib" | cut -d' ' -f1) \
     --ffi-search-path "$(dirname "$lib")" main.hy
# 1=a 2=b
# has a number
```

## Install

```bash
spool add regex --git https://github.com/ardax-corp/coil-regex.git --rev <commit SHA>
```

The repo has no tags yet, so pin a commit with `--rev`. Without spool, clone it next to your project and pass `--root ../coil-regex/src`. Either way the program must be granted libpcre2-8 (`--allow-dload pcre2-8` plus `--dload-pin` or `--dload-trusted`); see [consume.md](docs/consume.md).

## Test

```bash
make test COIL_ROOTS='--root ../coil-stdlib/src'   # tests and doc examples
```

Run the demo:

```bash
coil --root src --root ../coil-stdlib/src --allow-dload pcre2-8 --dload-pin pcre2-8=<sha256> --ffi-search-path <libdir> examples/regex_demo.hy
# true,2,a->1 b->2,a|b|c
```

## Docs

- [API](docs/api.md)
- [Consuming in a project](docs/consume.md)

## License

MIT — see [LICENSE](LICENSE).
