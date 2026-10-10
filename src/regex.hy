// Userland PCRE2 regex: binds libpcre2-8 directly (no C shim) and keeps the
// free-function API of the former virtual module.

use string::{from_bytes, to_bytes};

// PCRE2's 8-bit symbols. `pcre2.h` maps `pcre2_compile` to `pcre2_compile_8`
// with macros, so the real names carry the code-unit suffix.
extern "libpcre2-8.so.0" {
    fn pcre2_compile_8(string pattern, int length, uint32 options, [int] errorcode, [int] erroroffset, int ccontext) -> int;
    fn pcre2_code_free_8(int code);
    fn pcre2_match_data_create_from_pattern_8(int code, int gcontext) -> int;
    fn pcre2_match_data_free_8(int match_data);
    fn pcre2_match_8(int code, string subject, int length, int start_offset, uint32 options, int match_data, int mcontext) -> int32;
    fn pcre2_get_startchar_8(int match_data) -> int;
    fn pcre2_substring_length_bynumber_8(int match_data, uint32 number, [int] length) -> int32;
    fn pcre2_substring_copy_bynumber_8(int match_data, uint32 number, [int] buffer, [int] bufflen) -> int32;
    fn pcre2_substring_number_from_name_8(int code, string name) -> int32;
}

// Unsuffixed wrappers, so callers don't depend on the code-unit width.

/// `PCRE2_ZERO_TERMINATED`: `~(PCRE2_SIZE)0`.
const ZERO_TERMINATED: int = -1;

const PCRE2_CASELESS: int = 8;
const PCRE2_DOTALL: int = 32;
const PCRE2_EXTENDED: int = 128;
const PCRE2_MULTILINE: int = 1024;
const PCRE2_UCP: int = 131072;
const PCRE2_UTF: int = 524288;

const PCRE2_ERROR_NOMATCH: int = -1;

fn pcre2_compile(string pattern, int options) -> int {
    let errorcode = [0];
    let erroroffset = [0];
    return pcre2_compile_8(pattern, ZERO_TERMINATED, options, errorcode, erroroffset, 0);
}

fn pcre2_code_free(int code) {
    pcre2_code_free_8(code);
}

fn pcre2_match_data_create_from_pattern(int code) -> int {
    return pcre2_match_data_create_from_pattern_8(code, 0);
}

fn pcre2_match_data_free(int match_data) {
    pcre2_match_data_free_8(match_data);
}

fn pcre2_match(int code, string subject, int start_offset, int match_data) -> int {
    return pcre2_match_8(code, subject, ZERO_TERMINATED, start_offset, 0, match_data, 0);
}

fn pcre2_get_startchar(int match_data) -> int {
    return pcre2_get_startchar_8(match_data);
}

/// Byte length of group `number`, or a negative PCRE2 error (unset, …).
fn pcre2_substring_length_bynumber(int match_data, int number) -> int {
    let length = [0];
    let rc = pcre2_substring_length_bynumber_8(match_data, number, length);
    if rc < 0 {
        return rc;
    }
    return length[0];
}

/// Bytes of group `number` (`length` from the call above). The buffer is a
/// word array, so the copied bytes come back packed little-endian.
fn pcre2_substring_copy_bynumber(int match_data, int number, int length) -> Result<Vec<byte>, RegexError> {
    let words: Vec<int> = Vec::new();
    let nwords = length / 8 + 1;
    for _ in 0..nwords {
        words.push(0);
    }
    let bufflen = [nwords * 8];
    let rc = pcre2_substring_copy_bynumber_8(match_data, number, words, bufflen);
    if rc < 0 {
        raise RegexError::Runtime;
    }
    let out: Vec<byte> = Vec::new();
    for i in 0..length {
        out.push(((words[i / 8] >> ((i % 8) * 8)) & 255) as byte);
    }
    return out;
}

fn pcre2_substring_number_from_name(int code, string name) -> int {
    return pcre2_substring_number_from_name_8(code, name);
}

enum RegexError {
    Compile,
    Runtime,
    NoMatch,
    Utf8,
}

class Regex {
    code: int,
    match_data: int,
    // Groups set by the last successful match (PCRE2's match return).
    count: int,
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

fn clamp_end(int end, int n) -> int {
    if end > n {
        return n;
    }
    return end;
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

fn slice_bytes(string subject, int start, int end) -> Result<string, RegexError> {
    let bytes = to_bytes(subject);
    let n = len(bytes);
    if start < 0 || end < start || start > n {
        raise RegexError::Runtime;
    }
    let end_use = clamp_end(end, n);
    let out: Vec<byte> = Vec::new();
    let i = start;
    while i < end_use {
        out.push(bytes[i]);
        i = i + 1;
    }
    return match from_bytes(out) {
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
    let code = pcre2_compile(pattern, opts);
    if code == 0 {
        raise RegexError::Compile;
    }
    let match_data = pcre2_match_data_create_from_pattern(code);
    if match_data == 0 {
        pcre2_code_free(code);
        raise RegexError::Runtime;
    }
    return new Regex(code, match_data, 0);
}

#[max_depth(4096)]
fn capture_row_from(Regex re, int i, Vec<string> row) -> Result<Vec<string>, RegexError> {
    if i >= re.count {
        return row;
    }
    row.push(re.capture_at(i)?);
    return capture_row_from(re, i + 1, row)?;
}

#[max_depth(4096)]
fn find_all_from(Regex re, string subject, int offset, Vec<(int, int)> spans) -> Result<Vec<(int, int)>, RegexError> {
    if !re.next_match(subject, offset)? {
        return spans;
    }
    let span = re.span()?;
    spans.push(span);
    return find_all_from(re, subject, advance_offset(span.1, span.0), spans)?;
}

#[max_depth(4096)]
fn captures_all_from(Regex re, string subject, int offset, Vec<Vec<string>> rows) -> Result<Vec<Vec<string>>, RegexError> {
    if !re.next_match(subject, offset)? {
        return rows;
    }
    let span = re.span()?;
    rows.push(re.capture_row()?);
    return captures_all_from(re, subject, advance_offset(span.1, span.0), rows)?;
}

#[max_depth(4096)]
fn replace_all_from(Regex re, string subject, string template, int pos, string out, bool replaced) -> Result<string, RegexError> {
    if !re.next_match(subject, pos)? {
        if !replaced {
            return subject;
        }
        return out + slice_bytes(subject, pos, len(to_bytes(subject)))?;
    }
    let span = re.span()?;
    let head = slice_bytes(subject, pos, span.0)?;
    let piece = re.expand_replacement(template)?;
    return replace_all_from(re, subject, template, advance_offset(span.1, span.0), out + head + piece, true)?;
}

impl Regex {
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
        if offset > len(to_bytes(subject)) {
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
        return true;
    }

    /// Byte span of the last match. The start is where the match began, so
    /// a pattern using `\K` reports the span from before the `\K`.
    fn span() -> Result<(int, int), RegexError> {
        let start = pcre2_get_startchar(self.match_data);
        let length = pcre2_substring_length_bynumber(self.match_data, 0);
        if length < 0 {
            raise RegexError::Runtime;
        }
        return (start, start + length);
    }

    /// Text of group `index` in the last match; empty when unset or out of range.
    fn capture_at(int index) -> Result<string, RegexError> {
        if index < 0 || index >= self.count {
            return "";
        }
        let length = pcre2_substring_length_bynumber(self.match_data, index);
        if length <= 0 {
            return "";
        }
        let bytes = pcre2_substring_copy_bynumber(self.match_data, index, length)?;
        return match from_bytes(bytes) {
            Result::Ok(s) => s,
            Result::Err(_) => raise RegexError::Utf8,
        };
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
        return capture_row_from(self, 0, Vec::new())?;
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
                let name = slice_bytes(template, start, i)?;
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
                let idx = parse_usize(slice_bytes(template, start, i)?);
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
        let n = len(to_bytes(subject));
        while true {
            if !self.next_match(subject, offset)? {
                parts.push(slice_bytes(subject, offset, n)?);
                return parts;
            }
            let span = self.span()?;
            parts.push(slice_bytes(subject, offset, span.0)?);
            offset = advance_offset(span.1, span.0);
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
        return find_all_from(self, subject, 0, Vec::new())?;
    }

    pub fn captures(string subject) -> Result<Vec<string>, RegexError> {
        if !self.next_match(subject, 0)? {
            raise RegexError::NoMatch;
        }
        return self.capture_row()?;
    }

    pub fn captures_all(string subject) -> Result<Vec<Vec<string>>, RegexError> {
        return captures_all_from(self, subject, 0, Vec::new())?;
    }

    pub fn replace(string subject, string template) -> Result<string, RegexError> {
        if !self.next_match(subject, 0)? {
            return subject;
        }
        let span = self.span()?;
        let head = slice_bytes(subject, 0, span.0)?;
        let tail = slice_bytes(subject, span.1, len(to_bytes(subject)))?;
        let piece = self.expand_replacement(template)?;
        return head + piece + tail;
    }

    pub fn replace_all(string subject, string template) -> Result<string, RegexError> {
        return replace_all_from(self, subject, template, 0, "", false)?;
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
