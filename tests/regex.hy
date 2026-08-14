use regex::{Regex, compile, find, find_all, is_match, replace_all, split};

fn must_ok(Result r) -> Regex {
    return match r {
        Result::Ok(v) => v,
        Result::Err(_) => panic "expected Ok",
    };
}

test("compile bad flags is Compile") {
    let r = compile("a", "Z");
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(_) => {},
    };
}

test("compile bad pattern is Compile") {
    let r = compile("(", "");
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(_) => {},
    };
}

test("is_match respects caseless flag") {
    let re = must_ok(compile("abc", "i"));
    match is_match(re, "ABC") {
        Result::Ok(b) => assert(b)?,
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
    let r = find(re, "abc");
    match r {
        Result::Ok(_) => panic "expected Err",
        Result::Err(_) => {},
    };
}

test("find_all empty subject is empty not NoMatch") {
    let re = must_ok(compile("a", ""));
    let spans = match find_all(re, "") {
        Result::Ok(s) => s,
        Result::Err(_) => panic "find_all empty",
    };
    assert(spans.len() == 0)?;
}
