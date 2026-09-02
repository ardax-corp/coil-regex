use regex::{Regex, RegexError, compile, find, find_all, is_match, replace, replace_all, split};

fn must_ok(Result r) -> Regex {
    return match r {
        Result::Ok(v) => v,
        Result::Err(_) => panic "expected Ok",
    };
}

fn expect_compile(Result r) {
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(e) => match e {
            RegexError::Compile => {},
            default => panic "expected Compile",
        },
    };
}

fn expect_nomatch(Result r) {
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(e) => match e {
            RegexError::NoMatch => {},
            default => panic "expected NoMatch",
        },
    };
}

fn expect_runtime(Result r) {
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(e) => match e {
            RegexError::Runtime => {},
            default => panic "expected Runtime",
        },
    };
}

fn expect_utf8(Result r) {
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(e) => match e {
            RegexError::Utf8 => {},
            default => panic "expected Utf8",
        },
    };
}

test("compile bad flags is Compile") {
    expect_compile(compile("a", "Z"));
}

test("compile bad pattern is Compile") {
    expect_compile(compile("(", ""));
}

test("is_match respects caseless flag") {
    let re = must_ok(compile("abc", "i"));
    match is_match(re, "ABC") {
        Result::Ok(b) => assert(b)?,
        Result::Err(_) => panic "is_match failed",
    };
}

test("is_match is false when no match") {
    let re = must_ok(compile("xyz", ""));
    match is_match(re, "abc") {
        Result::Ok(b) => assert(!b)?,
        Result::Err(_) => panic "is_match failed",
    };
}

test("find_all split replace_all golden") {
    let re = must_ok(compile("(\\w+)=(\\d+)", ""));
    let spans = match find_all(re, "a=1 b=2") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find_all",
    };
    assert(spans.len() == 2)?;
    assert(spans[0][0] == 0)?;
    assert(spans[0][1] == 3)?;
    assert(spans[1][0] == 4)?;
    assert(spans[1][1] == 7)?;
    let out = match replace_all(re, "a=1 b=2", "$1->$2") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "replace_all",
    };
    assert(out == "a->1 b->2")?;
    let sep = must_ok(compile(",", ""));
    let parts = match split(sep, "a,b,c") {
        Result::Ok(p) => p,
        Result::Err(_) => panic "split",
    };
    assert(parts.len() == 3)?;
    assert(parts[0] == "a")?;
    assert(parts[1] == "b")?;
    assert(parts[2] == "c")?;
}

test("find no match is NoMatch") {
    let re = must_ok(compile("xyz", ""));
    expect_nomatch(find(re, "abc"));
}

test("find returns byte span") {
    let re = must_ok(compile("ll", ""));
    let span = match find(re, "hello") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find",
    };
    assert(span[0] == 2)?;
    assert(span[1] == 4)?;
}

test("find utf8 span is bytes not codepoints") {
    let re = must_ok(compile("é", ""));
    let span = match find(re, "café") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find utf8",
    };
    assert(span[0] == 3)?;
    assert(span[1] == 5)?;
}

test("find_all empty subject is empty not NoMatch") {
    let re = must_ok(compile("a", ""));
    let spans = match find_all(re, "") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find_all empty",
    };
    assert(spans.len() == 0)?;
}

test("find_all no match is empty not NoMatch") {
    let re = must_ok(compile("xyz", ""));
    let spans = match find_all(re, "abc") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find_all no match",
    };
    assert(spans.len() == 0)?;
}

test("flag m makes caret match after newline") {
    let plain = must_ok(compile("^b", ""));
    match is_match(plain, "a\nb") {
        Result::Ok(b) => assert(!b)?,
        Result::Err(_) => panic "is_match m off",
    };
    let multi = must_ok(compile("^b", "m"));
    match is_match(multi, "a\nb") {
        Result::Ok(b) => assert(b)?,
        Result::Err(_) => panic "is_match m on",
    };
}

test("flag s makes dot match newline") {
    let plain = must_ok(compile("a.b", ""));
    match is_match(plain, "a\nb") {
        Result::Ok(b) => assert(!b)?,
        Result::Err(_) => panic "is_match s off",
    };
    let dotall = must_ok(compile("a.b", "s"));
    match is_match(dotall, "a\nb") {
        Result::Ok(b) => assert(b)?,
        Result::Err(_) => panic "is_match s on",
    };
}

test("flag x ignores pattern whitespace") {
    let plain = must_ok(compile("a b", ""));
    match is_match(plain, "ab") {
        Result::Ok(b) => assert(!b)?,
        Result::Err(_) => panic "is_match x off",
    };
    let ext = must_ok(compile("a b", "x"));
    match is_match(ext, "ab") {
        Result::Ok(b) => assert(b)?,
        Result::Err(_) => panic "is_match x on",
    };
}

test("flag u makes word class unicode") {
    let ascii = must_ok(compile("\\w+", ""));
    match is_match(ascii, "é") {
        Result::Ok(b) => assert(!b)?,
        Result::Err(_) => panic "is_match u off",
    };
    let ucp = must_ok(compile("\\w+", "u"));
    match is_match(ucp, "é") {
        Result::Ok(b) => assert(b)?,
        Result::Err(_) => panic "is_match u on",
    };
}

test("replace first match only") {
    let re = must_ok(compile("(\\w+)=(\\d+)", ""));
    let out = match replace(re, "a=1 b=2", "$1->$2") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "replace",
    };
    assert(out == "a->1 b=2")?;
}

test("replace no match returns subject") {
    let re = must_ok(compile("xyz", ""));
    let out = match replace(re, "abc", "nope") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "replace no match",
    };
    assert(out == "abc")?;
}

test("replace named capture") {
    let re = must_ok(compile("(?<k>\\w+)=(?<v>\\d+)", ""));
    let out = match replace(re, "a=1 b=2", "${k}->${v}") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "replace named",
    };
    assert(out == "a->1 b=2")?;
}

test("replace_all literal dollar") {
    let re = must_ok(compile("a", ""));
    let out = match replace_all(re, "a b a", "$$") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "replace_all dollar",
    };
    assert(out == "$ b $")?;
}

test("replace unclosed named template is Runtime") {
    let re = must_ok(compile("a", ""));
    expect_runtime(replace(re, "a", "${oops"));
}

test("replace mid utf8 slice is Utf8") {
    let re = must_ok(compile("\\C", ""));
    expect_utf8(replace(re, "é", "x"));
}
