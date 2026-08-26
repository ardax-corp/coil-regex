use regex::{RegexError, compile, captures, captures_all, replace_all};

test("captures group text") {
    let re = match compile("(a)(b)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let row = match captures(re, "ab") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "captures",
    };
    assert(row.len() == 3)?;
    assert(row[1] == "a")?;
    assert(row[2] == "b")?;
}

test("captures no match is NoMatch") {
    let re = match compile("xyz", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    match captures(re, "abc") {
        Result::Ok(_) => panic "expected Err",
        Result::Err(e) => match e {
            RegexError::NoMatch => {},
            _ => panic "expected NoMatch",
        },
    };
}

test("captures_all rows") {
    let re = match compile("(\\w+)=(\\d+)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let rows = match captures_all(re, "a=1 b=2") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "captures_all",
    };
    assert(rows.len() == 2)?;
    let first = rows[0];
    assert(first.len() == 3)?;
    assert(first[0] == "a=1")?;
    assert(first[1] == "a")?;
    assert(first[2] == "1")?;
    let second = rows[1];
    assert(second[0] == "b=2")?;
    assert(second[1] == "b")?;
    assert(second[2] == "2")?;
}

test("captures_all empty is empty not NoMatch") {
    let re = match compile("a", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let rows = match captures_all(re, "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "captures_all empty",
    };
    assert(rows.len() == 0)?;
}

test("replace_all substitution") {
    let re = match compile("(\\w+)=(\\d+)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let out = match replace_all(re, "a=1", "$1->$2") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "replace",
    };
    assert(out == "a->1")?;
}
