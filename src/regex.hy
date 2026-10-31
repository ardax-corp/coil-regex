// Regular expressions for coil, backed by PCRE2: `compile` a pattern into a
// `Regex`, then search, capture, split and replace with its methods (or the
// free functions of the same names). Binds libpcre2-8 directly through FFI
// (no C shim); `Regex` is also a `text::Pattern` for the string methods.

use ffi::{declare, dload, invoke, read_ints};
use ffi::types::{ConstBytes, Int, Ptr, String};
use string::{from_bytes, slice_bytes, to_bytes};
use text::{Pattern, Span};

// libpcre2-8's 8-bit symbols. `pcre2.h` maps `pcre2_compile` to
// `pcre2_compile_8` with macros, so the real names carry the code-unit
// suffix. C `int` / `uint32_t` travel as `int`: arguments only use the low
// 32 bits, and results go through `c_int`.
extern "libpcre2-8.so.0" {
    fn pcre2_code_free_8(int code);
    fn pcre2_match_data_create_from_pattern_8(int code, int gcontext) -> int;
    fn pcre2_match_data_free_8(int match_data);
    fn pcre2_get_startchar_8(int match_data) -> int;
    fn pcre2_get_ovector_pointer_8(int match_data) -> int;
    fn pcre2_substring_number_from_name_8(int code, string name) -> int;
}

// `PCRE2_ZERO_TERMINATED`: `~(PCRE2_SIZE)0`.
const ZERO_TERMINATED = -1;

const PCRE2_CASELESS = 8;
const PCRE2_DOTALL = 32;
const PCRE2_EXTENDED = 128;
const PCRE2_MULTILINE = 1024;
const PCRE2_UCP = 131072;
const PCRE2_UTF = 524288;

const PCRE2_ERROR_NOMATCH = -1;

// Match-time options: the match must start at the start offset, or end at
// the end of the subject.
const PCRE2_ANCHORED = 2147483648;
const PCRE2_ENDANCHORED = 536870912;

// Coil strings are always valid UTF-8, so PCRE2 need not re-check the whole
// subject on every match. The start offset must still be a char boundary.
const PCRE2_NO_UTF_CHECK = 1073741824;

// Sign-extend a C `int` result from the low 32 bits of the return register.
fn c_int(int raw) -> int {
    let low = raw & 4294967295;
    if low >= 2147483648 {
        return low - 4294967296;
    }
    return low;
}

// Unsuffixed wrappers, so callers don't depend on the code-unit width.

fn pcre2_code_free(int code) {
    pcre2_code_free_8(code);
}

fn pcre2_match_data_create_from_pattern(int code) -> int {
    return pcre2_match_data_create_from_pattern_8(code, 0);
}

fn pcre2_match_data_free(int match_data) {
    pcre2_match_data_free_8(match_data);
}

fn pcre2_get_startchar(int match_data) -> int {
    return pcre2_get_startchar_8(match_data);
}

fn pcre2_get_ovector_pointer(int match_data) -> int {
    return pcre2_get_ovector_pointer_8(match_data);
}

fn pcre2_substring_number_from_name(int code, string name) -> int {
    return c_int(pcre2_substring_number_from_name_8(code, name));
}

// `pcre2_compile` writes its error through out-parameters, which `extern`
// blocks can't declare, so it goes through `declare` / `invoke`, where an
// int array argument is copied back after the call.
class Pcre2 {
    lib: int,
    compile_id: int,
    match_id: int,
}

fn ffi_ok(Result r) -> Result<int, RegexError> {
    return match r {
        Result::Ok(v) => v,
        Result::Err(_) => raise RegexError::Runtime,
    };
}

// One dload per process: every `Regex` shares these ids.
static let pcre2_lib = 0;
static let pcre2_compile_id = 0;
static let pcre2_match_id = 0;

fn pcre2_open() -> Result<Pcre2, RegexError> {
    if pcre2_lib == 0 {
        let lib = ffi_ok(dload("libpcre2-8.so.0"))?;
        pcre2_compile_id = ffi_ok(declare(lib, "pcre2_compile_8", (String, Int, Int, Ptr, Ptr, Int), Int))?;
        // `ConstBytes` lends the subject's bytes in place; `String` would copy
        // the whole subject into a C string on every match.
        pcre2_match_id = ffi_ok(declare(lib, "pcre2_match_8", (Int, ConstBytes, Int, Int, Int, Int, Int), Int))?;
        pcre2_lib = lib;
    }
    return new Pcre2(pcre2_lib, pcre2_compile_id, pcre2_match_id);
}

// A one-word out-parameter. Never empty: an empty array would be passed as
// a raw pointer instead of a copied buffer.
fn out_word(int initial) -> Vec<int> {
    let v: Vec<int> = Vec::new();
    v.push(initial);
    return v;
}

impl Pcre2 {
    // Compiled pattern, or 0 when it does not compile.
    pub fn compile(string pattern, int options) -> Result<int, RegexError> {
        let errorcode = out_word(0);
        let erroroffset = out_word(0);
        // A bare global in an `invoke` tuple reads as a callback; pass a local.
        let length = ZERO_TERMINATED;
        return ffi_ok(invoke(self.lib, self.compile_id, (pattern, length, options, errorcode, erroroffset, 0)))?;
    }

    // Match `subject` from byte `start_offset` with the match-time
    // `options`; the PCRE2 return code. Captures are sliced out of the coil
    // string by offset, so PCRE2 never reads the subject after the call and
    // needs no copy of it.
    pub fn match_at(int code, string subject, int start_offset, int match_data, int options) -> Result<int, RegexError> {
        let length = subject.len();
        // An offset inside a UTF-8 sequence is undefined behaviour under
        // `PCRE2_NO_UTF_CHECK`; let PCRE2 check (and reject) that one.
        if start_offset >= length || ((subject[start_offset] as int) & 192) != 128 {
            options = options | PCRE2_NO_UTF_CHECK;
        }
        let rc = ffi_ok(invoke(self.lib, self.match_id, (code, subject, length, start_offset, options, match_data, 0)))?;
        return c_int(rc);
    }

    // The first `count` offset pairs at `ovector`, as `2 * count` ints.
    pub fn offsets(int ovector, int count) -> Result<Vec<int>, RegexError> {
        return match read_ints(self.lib, ovector, count * 2) {
            Result::Ok(v) => v,
            Result::Err(_) => raise RegexError::Runtime,
        };
    }
}

/// The error of every fallible `regex` call.
///
/// Not finding a match is not an error: `find` and `captures` return
/// `Ok(None)`, `find_all` an empty vector, and `is_match` `Ok(false)`.
///
/// # Examples
///
/// ```
/// use regex::{compile, RegexError};
/// # use tests::assert;
/// assert!(compile("(", "").err() == Option::Some(RegexError::Compile));
/// assert!(compile("a", "Z").err() == Option::Some(RegexError::Compile));
/// ```
enum RegexError {
    /// The pattern does not compile, or the flags hold a letter other than
    /// `i`, `m`, `s`, `x` or `u`.
    Compile,
    /// PCRE2 failed while matching (for example, it hit its match limit),
    /// libpcre2-8 could not be loaded, or a replacement template has an
    /// unterminated `${`.
    Runtime,
    /// A capture or slice of the subject is not valid UTF-8.
    Utf8,
}

/// A compiled regular expression, made by `compile`.
///
/// Every search method returns a `Result<_, RegexError>`. Match positions are
/// byte offsets into the UTF-8 subject, not character indices. A `Regex`
/// remembers its last match (`expand_template` reads it), so it is not safe
/// to share between threads: compile one per thread. The PCRE2 code and match
/// data are freed when the `Regex` is dropped.
///
/// `Regex` implements `text::Pattern`, so the `text::Searchable` string
/// methods (`contains`, `split`, `replace_all`, `starts_with`, ...) take it
/// wherever they take a literal. Those methods panic on a PCRE2 match failure;
/// call the `Regex` methods to get a `Result` instead.
///
/// # Examples
///
/// ```
/// use regex::{compile};
/// use text::{Searchable};
/// # use tests::assert;
/// let digits = compile("[0-9]+", "").ok() ?? panic "bad pattern";
/// assert!(digits.is_match("build 42") == Result::Ok(true));
/// assert!(digits.find("build 42") == Result::Ok(Option::Some((6, 8))));
///
/// // As a `text::Pattern`:
/// assert!("build 42".contains(digits));
/// let parts = "a1b22c".split(digits);
/// assert!(parts.len() == 3 && parts[0] == "a" && parts[2] == "c");
/// ```
class Regex {
    pcre2: Pcre2,
    code: int,
    match_data: int,
    // PCRE2's offset vector inside `match_data`; fixed for its lifetime.
    ovector: int,
    // Groups set by the last successful match (PCRE2's match return).
    count: int,
    // Subject of the last match, which captures are sliced from.
    subject: string,
    // Offset pairs of the last match, read on first use; empty until then.
    offsets: Vec<int>,
}

fn parse_flags(string flags) -> int {
    let opts = PCRE2_UTF;
    let bytes = to_bytes(flags);
    for i in 0..bytes.len() {
        let c = bytes[i] as int;
        if c == 105 {
            opts = opts | PCRE2_CASELESS;
        } else if c == 109 {
            opts = opts | PCRE2_MULTILINE;
        } else if c == 115 {
            opts = opts | PCRE2_DOTALL;
        } else if c == 120 {
            opts = opts | PCRE2_EXTENDED;
        } else if c == 117 {
            opts = opts | PCRE2_UCP;
        } else {
            return 0;
        }
    }
    return opts;
}

// Where the next search starts after a match `[start, next)`. An empty match
// steps over one whole character, so the offset never lands inside a UTF-8
// sequence (PCRE2 rejects that).
fn advance_offset(string subject, int next, int start) -> int {
    if next > start {
        return next;
    }
    let i = next + 1;
    let n = subject.len();
    while i < n && ((subject[i] as int) & 192) == 128 {
        i = i + 1;
    }
    return i;
}

fn parse_usize(string digits) -> int {
    let bytes = to_bytes(digits);
    let n = bytes.len();
    let idx = 0;
    let i = 0;
    while i < n {
        idx = idx * 10 + ((bytes[i] as int) - 48);
        i = i + 1;
    }
    return idx;
}

fn byte_slice(string subject, int start, int end) -> Result<string, RegexError> {
    if start < 0 || end < start || start > subject.len() {
        raise RegexError::Runtime;
    }
    return match slice_bytes(subject, start, end) {
        Result::Ok(s) => s,
        Result::Err(_) => raise RegexError::Utf8,
    };
}

fn push_all(Vec<byte> out, string s) {
    let bytes = to_bytes(s);
    let j = 0;
    while j < bytes.len() {
        out.push(bytes[j]);
        j = j + 1;
    }
}

/// Compiles `pattern` (PCRE2 syntax) with the option letters in `flags`.
///
/// UTF-8 mode is always on. `flags` is any mix of these letters, or `""`:
///
/// | Flag | Meaning |
/// |------|---------|
/// | `i` | caseless |
/// | `m` | multiline: `^` and `$` match at each line |
/// | `s` | `.` also matches a newline |
/// | `x` | extended: whitespace and `#` comments in the pattern are ignored |
/// | `u` | Unicode properties for `\w`, `\d`, `\b` and the POSIX classes |
///
/// Backslashes are escaped in coil string literals, so the pattern `\d+` is
/// written `"\\d+"`.
///
/// # Errors
///
/// `RegexError::Compile` for a pattern PCRE2 rejects or an unknown flag
/// letter; `RegexError::Runtime` when libpcre2-8 cannot be loaded.
///
/// # Examples
///
/// ```
/// use regex::{compile};
/// # use tests::assert;
/// let re = compile("hello", "i").ok() ?? panic "bad pattern";
/// assert!(re.is_match("Say HELLO") == Result::Ok(true));
/// assert!(compile("(unclosed", "").is_err());
/// ```
fn compile(string pattern, string flags) -> Result<Regex, RegexError> {
    let opts = parse_flags(flags);
    if opts == 0 {
        raise RegexError::Compile;
    }
    let pcre2 = pcre2_open()?;
    let code = pcre2.compile(pattern, opts)?;
    if code == 0 {
        raise RegexError::Compile;
    }
    let match_data = pcre2_match_data_create_from_pattern(code);
    if match_data == 0 {
        pcre2_code_free(code);
        raise RegexError::Runtime;
    }
    let ovector = pcre2_get_ovector_pointer(match_data);
    return new Regex(pcre2, code, match_data, ovector, 0, "", Vec::new());
}

impl Regex {
    #[max_depth(4096)]
    fn capture_row_from(int i, Vec<string> row) -> Result<Vec<string>, RegexError> {
        if i >= self.count {
            return row;
        }
        row.push(self.capture_at(i)?);
        return self.capture_row_from(i + 1, row)?;
    }

    #[max_depth(4096)]
    fn find_all_from(string subject, int offset, Vec<(int, int)> spans) -> Result<Vec<(int, int)>, RegexError> {
        if !self.next_match(subject, offset)? {
            return spans;
        }
        let (start, end) = self.span()?;
        spans.push((start, end));
        return self.find_all_from(subject, advance_offset(subject, end, start), spans)?;
    }

    #[max_depth(4096)]
    fn captures_all_from(string subject, int offset, Vec<Vec<string>> rows) -> Result<Vec<Vec<string>>, RegexError> {
        if !self.next_match(subject, offset)? {
            return rows;
        }
        let (start, end) = self.span()?;
        rows.push(self.capture_row()?);
        return self.captures_all_from(subject, advance_offset(subject, end, start), rows)?;
    }

    #[max_depth(4096)]
    fn replace_all_from(string subject, string template, int pos, string out, bool replaced) -> Result<string, RegexError> {
        if !self.next_match(subject, pos)? {
            if !replaced {
                return subject;
            }
            return out + byte_slice(subject, pos, subject.len())?;
        }
        let (start, end) = self.span()?;
        let head = byte_slice(subject, pos, start)?;
        let piece = self.expand_replacement(template)?;
        return self.replace_all_from(subject, template, advance_offset(subject, end, start), out + head + piece, true)?;
    }

    fn drop() {
        if self.match_data != 0 {
            pcre2_match_data_free(self.match_data);
            self.match_data = 0;
        }
        if self.code != 0 {
            pcre2_code_free(self.code);
            self.code = 0;
        }
    }

    // Match from byte `offset`: `true` on a match, `false` on none.
    fn next_match(string subject, int offset) -> Result<bool, RegexError> {
        return self.next_match_with(subject, offset, 0)?;
    }

    // `next_match` with match-time PCRE2 `options` (`PCRE2_ANCHORED`, …).
    fn next_match_with(string subject, int offset, int options) -> Result<bool, RegexError> {
        if offset < 0 {
            raise RegexError::Runtime;
        }
        if offset > subject.len() {
            return false;
        }
        let rc = self.pcre2.match_at(self.code, subject, offset, self.match_data, options)?;
        if rc == PCRE2_ERROR_NOMATCH {
            return false;
        }
        if rc < 0 {
            raise RegexError::Runtime;
        }
        self.count = rc;
        self.subject = subject;
        self.offsets = Vec::new();
        return true;
    }

    // Offset pairs of the last match, read from PCRE2 once per match.
    fn match_offsets() -> Result<Vec<int>, RegexError> {
        if self.offsets.len() == 0 {
            self.offsets = self.pcre2.offsets(self.ovector, self.count)?;
        }
        return self.offsets;
    }

    // Byte span of the last match. The start is where the match began, so
    // a pattern using `\K` reports the span from before the `\K`.
    fn span() -> Result<(int, int), RegexError> {
        let start = pcre2_get_startchar(self.match_data);
        let ov = self.match_offsets()?;
        return (start, start + ov[1] - ov[0]);
    }

    // Text of group `index` in the last match; empty when unset or out of range.
    fn capture_at(int index) -> Result<string, RegexError> {
        if index < 0 || index >= self.count {
            return "";
        }
        let ov = self.match_offsets()?;
        let start = ov[index * 2];
        // An unset group's offsets are `PCRE2_UNSET` (`~(PCRE2_SIZE)0`).
        if start < 0 {
            return "";
        }
        return byte_slice(self.subject, start, ov[index * 2 + 1])?;
    }

    // Text of named group `name` in the last match; empty when unknown.
    fn capture_named(string name) -> Result<string, RegexError> {
        let index = pcre2_substring_number_from_name(self.code, name);
        if index < 0 {
            return "";
        }
        return self.capture_at(index)?;
    }

    fn capture_row() -> Result<Vec<string>, RegexError> {
        return self.capture_row_from(0, Vec::new())?;
    }

    fn expand_replacement(string template) -> Result<string, RegexError> {
        let bytes = to_bytes(template);
        let out: Vec<byte> = Vec::new();
        let i = 0;
        let n = bytes.len();
        while i < n {
            if bytes[i] != (36 as byte) {
                out.push(bytes[i]);
                i = i + 1;
                continue;
            }
            i = i + 1;
            if i >= n {
                out.push(36 as byte);
                break;
            }
            if bytes[i] == (36 as byte) {
                out.push(36 as byte);
                i = i + 1;
                continue;
            }
            if bytes[i] == (123 as byte) {
                i = i + 1;
                let start = i;
                while i < n {
                    if bytes[i] == (125 as byte) {
                        break;
                    }
                    i = i + 1;
                }
                if i >= n {
                    raise RegexError::Runtime;
                }
                let name = byte_slice(template, start, i)?;
                i = i + 1;
                push_all(out, self.capture_named(name)?);
                continue;
            }
            if bytes[i] >= (48 as byte) && bytes[i] <= (57 as byte) {
                let start = i;
                while i < n {
                    if bytes[i] < (48 as byte) || bytes[i] > (57 as byte) {
                        break;
                    }
                    i = i + 1;
                }
                let idx = parse_usize(byte_slice(template, start, i)?);
                push_all(out, self.capture_at(idx)?);
                continue;
            }
            out.push(36 as byte);
            out.push(bytes[i]);
            i = i + 1;
        }
        return match from_bytes(out) {
            Result::Ok(s) => s,
            Result::Err(_) => raise RegexError::Utf8,
        };
    }

    /// The pieces of `subject` between matches, in order.
    ///
    /// The text before the first match and after the last one are kept, so
    /// a match at either end gives an empty first or last piece, and `subject`
    /// without a match is one piece.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let sep = compile("\\s*,\\s*", "").ok() ?? panic "bad pattern";
    /// let parts = sep.split("a , b,c").unwrap_or(Vec::new());
    /// assert!(parts.len() == 3);
    /// assert!(parts[0] == "a" && parts[1] == "b" && parts[2] == "c");
    /// ```
    pub fn split(string subject) -> Result<Vec<string>, RegexError> {
        let parts: Vec<string> = Vec::new();
        let offset = 0;
        let n = subject.len();
        while true {
            if !self.next_match(subject, offset)? {
                parts.push(byte_slice(subject, offset, n)?);
                return parts;
            }
            let (start, end) = self.span()?;
            parts.push(byte_slice(subject, offset, start)?);
            offset = advance_offset(subject, end, start);
        }
    }

    /// Whether the pattern matches anywhere in `subject`.
    ///
    /// Anchor the pattern (`^...$`) to test the whole string.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("^[a-z]+$", "").ok() ?? panic "bad pattern";
    /// assert!(re.is_match("coil") == Result::Ok(true));
    /// assert!(re.is_match("coil 1") == Result::Ok(false));
    /// ```
    pub fn is_match(string subject) -> Result<bool, RegexError> {
        return self.next_match(subject, 0)?;
    }

    /// The first match, as `(start, end)` byte offsets; `None` when there is
    /// none.
    ///
    /// `subject[start..end]` is the matched text. The start is where the
    /// match began, so a pattern using `\K` reports the span from before the
    /// `\K`.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("[0-9]+", "").ok() ?? panic "bad pattern";
    /// assert!(re.find("id 314") == Result::Ok(Option::Some((3, 6))));
    /// assert!(re.find("none") == Result::Ok(Option::None));
    /// ```
    pub fn find(string subject) -> Result<Option<(int, int)>, RegexError> {
        return self.find_at(subject, 0)?;
    }

    /// The first match at or after byte offset `from`, as `(start, end)`
    /// byte offsets; `None` when there is none or `from` is past the end.
    ///
    /// Lookbehinds and `\b` still see the text before `from`.
    ///
    /// # Errors
    ///
    /// `RegexError::Runtime` when `from` is negative or inside a UTF-8
    /// sequence.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("o", "").ok() ?? panic "bad pattern";
    /// assert!(re.find_at("foo", 2) == Result::Ok(Option::Some((2, 3))));
    /// assert!(re.find_at("foo", 3) == Result::Ok(Option::None));
    /// ```
    pub fn find_at(string subject, int from) -> Result<Option<(int, int)>, RegexError> {
        if !self.next_match(subject, from)? {
            return Option::None;
        }
        return Option::Some(self.span()?);
    }

    /// Whether a match starts at the beginning of `subject` (PCRE2's
    /// `ANCHORED`). Backs `string.starts_with(re)`.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let year = compile("[0-9]{4}-", "").ok() ?? panic "bad pattern";
    /// assert!(year.matches_prefix("2026-10-31") == Result::Ok(true));
    /// assert!(year.matches_prefix("on 2026-10-31") == Result::Ok(false));
    /// ```
    pub fn matches_prefix(string subject) -> Result<bool, RegexError> {
        return self.next_match_with(subject, 0, PCRE2_ANCHORED)?;
    }

    /// Whether a match ends at the end of `subject` (PCRE2's `ENDANCHORED`).
    /// Backs `string.ends_with(re)`.
    ///
    /// A match ending at the end is found even when an earlier, shorter match
    /// does not end there: `a|ab` is a suffix of `"xab"`.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("a|ab", "").ok() ?? panic "bad pattern";
    /// assert!(re.matches_suffix("xab") == Result::Ok(true));
    /// assert!(re.matches_suffix("abx") == Result::Ok(false));
    /// ```
    pub fn matches_suffix(string subject) -> Result<bool, RegexError> {
        return self.next_match_with(subject, 0, PCRE2_ENDANCHORED)?;
    }

    /// `template` with `$n`, `${name}` and `$$` expanded from the last
    /// successful match of this `Regex`.
    ///
    /// `$n` (one or more digits) is group `n`, `${name}` a named group and
    /// `$$` a literal `$`. A group that did not take part, or does not
    /// exist, expands to `""`. A `$` followed by anything else is kept as is.
    /// Before any match every group is `""`.
    ///
    /// # Errors
    ///
    /// `RegexError::Runtime` for an unterminated `${`.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("(?<key>\\w+)=(\\d+)", "").ok() ?? panic "bad pattern";
    /// assert!(re.is_match("port=8080") == Result::Ok(true));
    /// assert!(re.expand_template("${key} is $2 ($$)") == Result::Ok("port is 8080 ($)"));
    /// ```
    pub fn expand_template(string template) -> Result<string, RegexError> {
        return self.expand_replacement(template)?;
    }

    /// Every non-overlapping match, left to right, as `(start, end)` byte
    /// offsets; empty when there is none.
    ///
    /// After an empty match the search moves on by one character, so a
    /// pattern that can match `""` still ends.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("[0-9]+", "").ok() ?? panic "bad pattern";
    /// let spans = re.find_all("a1 b22 c333").unwrap_or(Vec::new());
    /// assert!(spans.len() == 3);
    /// assert!(spans[1] == (4, 6));
    /// ```
    pub fn find_all(string subject) -> Result<Vec<(int, int)>, RegexError> {
        return self.find_all_from(subject, 0, Vec::new())?;
    }

    /// The groups of the first match, group 0 (the whole match) first;
    /// `None` when there is none.
    ///
    /// The vector holds group 0 up to the highest group that took part in
    /// the match; an unset group inside that range is `""`.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("(\\w+)@(\\w+)\\.com", "").ok() ?? panic "bad pattern";
    /// let groups = re.captures("mail ana@example.com").unwrap_or(Option::None) ?? Vec::new();
    /// assert!(groups.len() == 3);
    /// assert!(groups[0] == "ana@example.com" && groups[1] == "ana" && groups[2] == "example");
    /// ```
    pub fn captures(string subject) -> Result<Option<Vec<string>>, RegexError> {
        if !self.next_match(subject, 0)? {
            return Option::None;
        }
        return Option::Some(self.capture_row()?);
    }

    /// The groups of every non-overlapping match, one row per match in the
    /// shape `captures` returns; empty when there is none.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("(\\w)=(\\d)", "").ok() ?? panic "bad pattern";
    /// let rows = re.captures_all("a=1 b=2").unwrap_or(Vec::new());
    /// assert!(rows.len() == 2);
    /// assert!(rows[1][1] == "b" && rows[1][2] == "2");
    /// ```
    pub fn captures_all(string subject) -> Result<Vec<Vec<string>>, RegexError> {
        return self.captures_all_from(subject, 0, Vec::new())?;
    }

    /// `subject` with its first match replaced by `template`, expanded as in
    /// `expand_template` (`$n`, `${name}`, `$$`); `subject` unchanged when
    /// there is no match.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("(\\w+) (\\w+)", "").ok() ?? panic "bad pattern";
    /// assert!(re.replace("hello world, bye now", "$2 $1") == Result::Ok("world hello, bye now"));
    /// ```
    pub fn replace(string subject, string template) -> Result<string, RegexError> {
        if !self.next_match(subject, 0)? {
            return subject;
        }
        let (start, end) = self.span()?;
        let head = byte_slice(subject, 0, start)?;
        let tail = byte_slice(subject, end, subject.len())?;
        let piece = self.expand_replacement(template)?;
        return head + piece + tail;
    }

    /// `subject` with every non-overlapping match replaced by `template`,
    /// expanded per match as in `expand_template`; `subject` unchanged when
    /// there is no match.
    ///
    /// # Examples
    ///
    /// ```
    /// use regex::{compile};
    /// # use tests::assert;
    /// let re = compile("(\\w)=(\\d)", "").ok() ?? panic "bad pattern";
    /// assert!(re.replace_all("a=1 b=2", "$2:$1") == Result::Ok("1:a 2:b"));
    /// ```
    pub fn replace_all(string subject, string template) -> Result<string, RegexError> {
        return self.replace_all_from(subject, template, 0, "", false)?;
    }
}

/// `re.split(subject)`: the pieces of `subject` between matches.
fn split(Regex re, string subject) -> Result<Vec<string>, RegexError> {
    return re.split(subject)?;
}

/// `re.is_match(subject)`: whether `re` matches anywhere in `subject`.
fn is_match(Regex re, string subject) -> Result<bool, RegexError> {
    return re.is_match(subject)?;
}

/// `re.find(subject)`: the first match as `(start, end)` byte offsets, or `None`.
fn find(Regex re, string subject) -> Result<Option<(int, int)>, RegexError> {
    return re.find(subject)?;
}

/// `re.find_all(subject)`: every non-overlapping match as `(start, end)` byte
/// offsets.
///
/// # Examples
///
/// ```
/// use regex::{compile, find_all};
/// # use tests::assert;
/// let re = compile("o+", "").ok() ?? panic "bad pattern";
/// let spans = find_all(re, "foo boo").unwrap_or(Vec::new());
/// assert!(spans.len() == 2 && spans[0] == (1, 3));
/// ```
fn find_all(Regex re, string subject) -> Result<Vec<(int, int)>, RegexError> {
    return re.find_all(subject)?;
}

/// `re.captures(subject)`: the groups of the first match, or `None`.
fn captures(Regex re, string subject) -> Result<Option<Vec<string>>, RegexError> {
    return re.captures(subject)?;
}

/// `re.captures_all(subject)`: the groups of every match.
fn captures_all(Regex re, string subject) -> Result<Vec<Vec<string>>, RegexError> {
    return re.captures_all(subject)?;
}

/// `re.replace(subject, template)`: `subject` with its first match replaced.
fn replace(Regex re, string subject, string template) -> Result<string, RegexError> {
    return re.replace(subject, template)?;
}

/// `re.replace_all(subject, template)`: `subject` with every match replaced.
///
/// # Examples
///
/// ```
/// use regex::{compile, replace_all};
/// # use tests::assert;
/// let re = compile("\\s+", "").ok() ?? panic "bad pattern";
/// assert!(replace_all(re, "a  b\tc", " ") == Result::Ok("a b c"));
/// ```
fn replace_all(Regex re, string subject, string template) -> Result<string, RegexError> {
    return re.replace_all(subject, template)?;
}

fn must_match(Result<bool, RegexError> r) -> bool {
    return match r {
        Result::Ok(found) => found,
        Result::Err(_) => panic "regex: PCRE2 match failed",
    };
}

// A `Regex` is a `text::Pattern`, so the `text::Searchable` methods take it:
// `"foobar".contains(re)`, `line.split(re)`, `s.replace_all(re, "$1")`.
// A PCRE2 failure while matching (such as its match limit) panics.
impl Pattern for Regex {
    /// The first match at or after byte `from`, as a `text::Span`. Panics on a
    /// PCRE2 match failure.
    pub fn find_in(Regex re, string hay, int from) -> Option<Span> {
        return match re.find_at(hay, from) {
            Result::Ok(Option::Some(span)) => Option::Some(new Span(span[0], span[1])),
            Result::Ok(Option::None) => Option::None,
            Result::Err(_) => panic "regex: PCRE2 match failed",
        };
    }

    /// Whether a match starts at the beginning of `hay`. Panics on a PCRE2
    /// match failure.
    pub fn is_prefix_of(Regex re, string hay) -> bool {
        return must_match(re.matches_prefix(hay));
    }

    /// Whether a match ends at the end of `hay`. Panics on a PCRE2 match
    /// failure.
    pub fn is_suffix_of(Regex re, string hay) -> bool {
        return must_match(re.matches_suffix(hay));
    }

    /// `template` expanded from the last match, as in `Regex::expand_template`.
    /// Panics on an unterminated `${`.
    pub fn expand(Regex re, string template) -> string {
        return match re.expand_template(template) {
            Result::Ok(s) => s,
            Result::Err(_) => panic "regex: bad replacement template",
        };
    }
}
