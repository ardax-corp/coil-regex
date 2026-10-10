// Userland PCRE2 regex: binds libpcre2-8 directly (no C shim) and keeps the
// free-function API of the former virtual module.

use ffi::{declare, dload, invoke, read_ints};
use ffi::types::{Int, Ptr, String};
use string::{from_bytes, slice_bytes, to_bytes};

// libpcre2-8's 8-bit symbols. `pcre2.h` maps `pcre2_compile` to
// `pcre2_compile_8` with macros, so the real names carry the code-unit
// suffix. C `int` / `uint32_t` travel as `int`: arguments only use the low
// 32 bits, and results go through `c_int`.
extern "libpcre2-8.so.0" {
    fn pcre2_code_free_8(int code);
    fn pcre2_match_data_create_from_pattern_8(int code, int gcontext) -> int;
    fn pcre2_match_data_free_8(int match_data);
    fn pcre2_match_8(int code, string subject, int length, int start_offset, int options, int match_data, int mcontext) -> int;
    fn pcre2_get_startchar_8(int match_data) -> int;
    fn pcre2_get_ovector_pointer_8(int match_data) -> int;
    fn pcre2_substring_number_from_name_8(int code, string name) -> int;
}

// `PCRE2_ZERO_TERMINATED`: `~(PCRE2_SIZE)0`.
static const ZERO_TERMINATED = -1;

static const PCRE2_CASELESS = 8;
static const PCRE2_DOTALL = 32;
static const PCRE2_EXTENDED = 128;
static const PCRE2_MULTILINE = 1024;
static const PCRE2_UCP = 131072;
static const PCRE2_UTF = 524288;

static const PCRE2_ERROR_NOMATCH = -1;

/// Sign-extend a C `int` result from the low 32 bits of the return register.
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

// Captures are sliced out of the coil string by offset, so PCRE2 never reads
// the subject after the call and needs no copy of it.
fn pcre2_match(int code, string subject, int start_offset, int match_data) -> int {
    let rc = pcre2_match_8(code, subject, ZERO_TERMINATED, start_offset, 0, match_data, 0);
    return c_int(rc);
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

/// `pcre2_compile` writes its error through out-parameters, which `extern`
/// blocks can't declare, so it goes through `declare` / `invoke`, where an
/// int array argument is copied back after the call.
class Pcre2 {
    lib: int,
    compile_id: int,
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

fn pcre2_open() -> Result<Pcre2, RegexError> {
    if pcre2_lib == 0 {
        let lib = ffi_ok(dload("libpcre2-8.so.0"))?;
        pcre2_compile_id = ffi_ok(declare(lib, "pcre2_compile_8", (String, Int, Int, Ptr, Ptr, Int), Int))?;
        pcre2_lib = lib;
    }
    return new Pcre2(pcre2_lib, pcre2_compile_id);
}

/// A one-word out-parameter. Never empty: an empty array would be passed as
/// a raw pointer instead of a copied buffer.
fn out_word(int initial) -> Vec<int> {
    let v: Vec<int> = Vec::new();
    v.push(initial);
    return v;
}

impl Pcre2 {
    /// Compiled pattern, or 0 when it does not compile.
    pub fn compile(string pattern, int options) -> Result<int, RegexError> {
        let errorcode = out_word(0);
        let erroroffset = out_word(0);
        // A bare global in an `invoke` tuple reads as a callback; pass a local.
        let length = ZERO_TERMINATED;
        return ffi_ok(invoke(self.lib, self.compile_id, (pattern, length, options, errorcode, erroroffset, 0)))?;
    }

    /// The first `count` offset pairs at `ovector`, as `2 * count` ints.
    pub fn offsets(int ovector, int count) -> Result<Vec<int>, RegexError> {
        return match read_ints(self.lib, ovector, count * 2) {
            Result::Ok(v) => v,
            Result::Err(_) => raise RegexError::Runtime,
        };
    }
}

enum RegexError {
    Compile,
    Runtime,
    NoMatch,
    Utf8,
}

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
    for i in 0..len(bytes) {
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

fn advance_offset(int next, int start) -> int {
    if next <= start {
        return next + 1;
    }
    return next;
}

fn parse_usize(string digits) -> int {
    let bytes = to_bytes(digits);
    let n = len(bytes);
    let idx = 0;
    let i = 0;
    while i < n {
        idx = idx * 10 + ((bytes[i] as int) - 48);
        i = i + 1;
    }
    return idx;
}

fn byte_slice(string subject, int start, int end) -> Result<string, RegexError> {
    if start < 0 || end < start || start > len(subject) {
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
    while j < len(bytes) {
        out.push(bytes[j]);
        j = j + 1;
    }
}

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
        return self.find_all_from(subject, advance_offset(end, start), spans)?;
    }

    #[max_depth(4096)]
    fn captures_all_from(string subject, int offset, Vec<Vec<string>> rows) -> Result<Vec<Vec<string>>, RegexError> {
        if !self.next_match(subject, offset)? {
            return rows;
        }
        let (start, end) = self.span()?;
        rows.push(self.capture_row()?);
        return self.captures_all_from(subject, advance_offset(end, start), rows)?;
    }

    #[max_depth(4096)]
    fn replace_all_from(string subject, string template, int pos, string out, bool replaced) -> Result<string, RegexError> {
        if !self.next_match(subject, pos)? {
            if !replaced {
                return subject;
            }
            return out + byte_slice(subject, pos, len(subject))?;
        }
        let (start, end) = self.span()?;
        let head = byte_slice(subject, pos, start)?;
        let piece = self.expand_replacement(template)?;
        return self.replace_all_from(subject, template, advance_offset(end, start), out + head + piece, true)?;
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

    /// Match from byte `offset`: `true` on a match, `false` on none.
    fn next_match(string subject, int offset) -> Result<bool, RegexError> {
        if offset < 0 {
            raise RegexError::Runtime;
        }
        if offset > len(subject) {
            return false;
        }
        let rc = pcre2_match(self.code, subject, offset, self.match_data);
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

    /// Offset pairs of the last match, read from PCRE2 once per match.
    fn match_offsets() -> Result<Vec<int>, RegexError> {
        if len(self.offsets) == 0 {
            self.offsets = self.pcre2.offsets(self.ovector, self.count)?;
        }
        return self.offsets;
    }

    /// Byte span of the last match. The start is where the match began, so
    /// a pattern using `\K` reports the span from before the `\K`.
    fn span() -> Result<(int, int), RegexError> {
        let start = pcre2_get_startchar(self.match_data);
        let ov = self.match_offsets()?;
        return (start, start + ov[1] - ov[0]);
    }

    /// Text of group `index` in the last match; empty when unset or out of range.
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

    /// Text of named group `name` in the last match; empty when unknown.
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
        let n = len(bytes);
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

    pub fn split(string subject) -> Result<Vec<string>, RegexError> {
        let parts: Vec<string> = Vec::new();
        let offset = 0;
        let n = len(subject);
        while true {
            if !self.next_match(subject, offset)? {
                parts.push(byte_slice(subject, offset, n)?);
                return parts;
            }
            let (start, end) = self.span()?;
            parts.push(byte_slice(subject, offset, start)?);
            offset = advance_offset(end, start);
        }
    }

    pub fn is_match(string subject) -> Result<bool, RegexError> {
        return self.next_match(subject, 0)?;
    }

    pub fn find(string subject) -> Result<(int, int), RegexError> {
        if !self.next_match(subject, 0)? {
            raise RegexError::NoMatch;
        }
        return self.span()?;
    }

    pub fn find_all(string subject) -> Result<Vec<(int, int)>, RegexError> {
        return self.find_all_from(subject, 0, Vec::new())?;
    }

    pub fn captures(string subject) -> Result<Vec<string>, RegexError> {
        if !self.next_match(subject, 0)? {
            raise RegexError::NoMatch;
        }
        return self.capture_row()?;
    }

    pub fn captures_all(string subject) -> Result<Vec<Vec<string>>, RegexError> {
        return self.captures_all_from(subject, 0, Vec::new())?;
    }

    pub fn replace(string subject, string template) -> Result<string, RegexError> {
        if !self.next_match(subject, 0)? {
            return subject;
        }
        let (start, end) = self.span()?;
        let head = byte_slice(subject, 0, start)?;
        let tail = byte_slice(subject, end, len(subject))?;
        let piece = self.expand_replacement(template)?;
        return head + piece + tail;
    }

    pub fn replace_all(string subject, string template) -> Result<string, RegexError> {
        return self.replace_all_from(subject, template, 0, "", false)?;
    }
}

fn split(Regex re, string subject) -> Result<Vec<string>, RegexError> {
    return re.split(subject)?;
}

fn is_match(Regex re, string subject) -> Result<bool, RegexError> {
    return re.is_match(subject)?;
}

fn find(Regex re, string subject) -> Result<(int, int), RegexError> {
    return re.find(subject)?;
}

fn find_all(Regex re, string subject) -> Result<Vec<(int, int)>, RegexError> {
    return re.find_all(subject)?;
}

fn captures(Regex re, string subject) -> Result<Vec<string>, RegexError> {
    return re.captures(subject)?;
}

fn captures_all(Regex re, string subject) -> Result<Vec<Vec<string>>, RegexError> {
    return re.captures_all(subject)?;
}

fn replace(Regex re, string subject, string template) -> Result<string, RegexError> {
    return re.replace(subject, template)?;
}

fn replace_all(Regex re, string subject, string template) -> Result<string, RegexError> {
    return re.replace_all(subject, template)?;
}
