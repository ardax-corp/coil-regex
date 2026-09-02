// Userland PCRE2 regex — FFI shim + free-function API matching the former virtual module.

use string::{from_bytes, to_bytes};

extern "regex" {
    fn coil_regex_compile(string pattern, string flags) -> int;
    fn coil_regex_free(int handle);
    fn coil_regex_is_match(int handle, string subject) -> int;
    fn coil_regex_find(int handle, string subject) -> int;
    fn coil_regex_next_match(int handle, string subject, int offset) -> int;
    fn coil_regex_capture_count(int handle) -> int;
    fn coil_regex_capture_at(int handle, int index) -> string;
    fn coil_regex_capture_named(int handle, string name) -> string;
    fn coil_regex_span_start(int packed) -> int;
    fn coil_regex_span_end(int packed) -> int;
}

enum RegexError {
    Compile,
    Runtime,
    NoMatch,
    Utf8,
}

class Regex {
    handle: int,
}

fn err_from_code(int code) -> RegexError {
    if code == -1 {
        return RegexError::Compile;
    }
    if code == -2 {
        return RegexError::Runtime;
    }
    if code == -3 {
        return RegexError::NoMatch;
    }
    if code == -4 {
        return RegexError::Utf8;
    }
    return RegexError::Runtime;
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

#[max_depth(4096)]
fn capture_row_from(int handle, int i, int count, Vec<string> row) -> Result<Vec<string>, RegexError> {
    if i >= count {
        return row;
    }
    row.push(coil_regex_capture_at(handle, i));
    return capture_row_from(handle, i + 1, count, row)?;
}

fn capture_row(int handle) -> Result<Vec<string>, RegexError> {
    let count = coil_regex_capture_count(handle);
    if count < 0 {
        raise err_from_code(count);
    }
    return capture_row_from(handle, 0, count, Vec::new())?;
}

#[max_depth(4096)]
fn find_all_from(int handle, string subject, int offset, Vec<(int, int)> spans) -> Result<Vec<(int, int)>, RegexError> {
    let packed = coil_regex_next_match(handle, subject, offset);
    if packed == -3 {
        return spans;
    }
    if packed < 0 {
        raise err_from_code(packed);
    }
    let start = coil_regex_span_start(packed);
    let end = coil_regex_span_end(packed);
    spans.push((start, end));
    return find_all_from(handle, subject, advance_offset(end, start), spans)?;
}

#[max_depth(4096)]
fn captures_all_from(int handle, string subject, int offset, Vec<Vec<string>> rows) -> Result<Vec<Vec<string>>, RegexError> {
    let packed = coil_regex_next_match(handle, subject, offset);
    if packed == -3 {
        return rows;
    }
    if packed < 0 {
        raise err_from_code(packed);
    }
    rows.push(capture_row(handle)?);
    let end = coil_regex_span_end(packed);
    let start = coil_regex_span_start(packed);
    return captures_all_from(handle, subject, advance_offset(end, start), rows)?;
}

fn compile(string pattern, string flags) -> Result<Regex, RegexError> {
    let h = coil_regex_compile(pattern, flags);
    if h == 0 {
        raise RegexError::Compile;
    }
    return new Regex(h);
}

fn expand_replacement(int handle, string template) -> Result<string, RegexError> {
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
            let cap = coil_regex_capture_named(handle, name);
            let cap_bytes = to_bytes(cap);
            let j = 0;
            while j < len(cap_bytes) {
                out.push(cap_bytes[j]);
                j = j + 1;
            }
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
            let cap = coil_regex_capture_at(handle, idx);
            let cap_bytes = to_bytes(cap);
            let j = 0;
            while j < len(cap_bytes) {
                out.push(cap_bytes[j]);
                j = j + 1;
            }
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

#[max_depth(4096)]
fn replace_all_from(int handle, string subject, string template, int pos, string out, bool replaced) -> Result<string, RegexError> {
    let packed = coil_regex_next_match(handle, subject, pos);
    if packed == -3 {
        let tail = slice_bytes(subject, pos, len(to_bytes(subject)))?;
        if !replaced {
            return subject;
        }
        return out + tail;
    }
    if packed < 0 {
        raise err_from_code(packed);
    }
    let start = coil_regex_span_start(packed);
    let end = coil_regex_span_end(packed);
    let head = slice_bytes(subject, pos, start)?;
    let piece = expand_replacement(handle, template)?;
    return replace_all_from(handle, subject, template, advance_offset(end, start), out + head + piece, true)?;
}

impl Regex {
    fn drop() {
        if self.handle != 0 {
            coil_regex_free(self.handle);
            self.handle = 0;
        }
    }

    pub fn split(string subject) -> Result<Vec<string>, RegexError> {
        let parts: Vec<string> = Vec::new();
        let offset = 0;
        let n = len(to_bytes(subject));
        while true {
            let packed = coil_regex_next_match(self.handle, subject, offset);
            if packed == -3 {
                parts.push(slice_bytes(subject, offset, n)?);
                return parts;
            }
            if packed < 0 {
                raise err_from_code(packed);
            }
            let start = coil_regex_span_start(packed);
            let end = coil_regex_span_end(packed);
            parts.push(slice_bytes(subject, offset, start)?);
            offset = advance_offset(end, start);
        }
    }

    pub fn is_match(string subject) -> Result<bool, RegexError> {
        let rc = coil_regex_is_match(self.handle, subject);
        if rc < 0 {
            raise err_from_code(rc);
        }
        return rc != 0;
    }

    pub fn find(string subject) -> Result<(int, int), RegexError> {
        let packed = coil_regex_find(self.handle, subject);
        if packed < 0 {
            raise err_from_code(packed);
        }
        return (coil_regex_span_start(packed), coil_regex_span_end(packed));
    }

    pub fn find_all(string subject) -> Result<Vec<(int, int)>, RegexError> {
        return find_all_from(self.handle, subject, 0, Vec::new())?;
    }

    pub fn captures(string subject) -> Result<Vec<string>, RegexError> {
        let packed = coil_regex_find(self.handle, subject);
        if packed < 0 {
            raise err_from_code(packed);
        }
        return capture_row(self.handle)?;
    }

    pub fn captures_all(string subject) -> Result<Vec<Vec<string>>, RegexError> {
        return captures_all_from(self.handle, subject, 0, Vec::new())?;
    }

    pub fn replace(string subject, string template) -> Result<string, RegexError> {
        let packed = coil_regex_find(self.handle, subject);
        if packed == -3 {
            return subject;
        }
        if packed < 0 {
            raise err_from_code(packed);
        }
        let start = coil_regex_span_start(packed);
        let end = coil_regex_span_end(packed);
        let head = slice_bytes(subject, 0, start)?;
        let tail = slice_bytes(subject, end, len(to_bytes(subject)))?;
        let piece = expand_replacement(self.handle, template)?;
        return head + piece + tail;
    }

    pub fn replace_all(string subject, string template) -> Result<string, RegexError> {
        return replace_all_from(self.handle, subject, template, 0, "", false)?;
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
