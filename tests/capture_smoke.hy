use tests::assert;
use regex::{RegexError, compile, captures, captures_all, replace_all};

test("captures group text") {
    let re = match compile("(a)(b)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let row = match captures(re, "ab") {
        Result::Ok(Option::Some(v)) => v,
        Result::Ok(Option::None) => panic "expected a match",
        Result::Err(_) => panic "captures",
    };
    assert!(row.len() == 3);
    assert!(row[1] == "a");
    assert!(row[2] == "b");
}

test("captures no match is None") {
    let re = match compile("xyz", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    match captures(re, "abc") {
        Result::Ok(Option::None) => {},
        Result::Ok(Option::Some(_)) => panic "expected None",
        Result::Err(_) => panic "expected Ok(None)",
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
    assert!(rows.len() == 2);
    let first = rows[0];
    assert!(first.len() == 3);
    assert!(first[0] == "a=1");
    assert!(first[1] == "a");
    assert!(first[2] == "1");
    let second = rows[1];
    assert!(second[0] == "b=2");
    assert!(second[1] == "b");
    assert!(second[2] == "2");
}

test("captures_all empty is empty") {
    let re = match compile("a", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let rows = match captures_all(re, "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "captures_all empty",
    };
    assert!(rows.len() == 0);
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
    assert!(out == "a->1");
}

test("captures longer than one word and multi-byte UTF-8") {
    let re = match compile("<(.+)>", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let row = match captures(re, "x<héllo wörld, a long capture>y") {
        Result::Ok(Option::Some(v)) => v,
        Result::Ok(Option::None) => panic "expected a match",
        Result::Err(_) => panic "captures",
    };
    assert!(row[1] == "héllo wörld, a long capture");
}

test("capture longer than the first-try buffer") {
    let re = match compile("\\[(.*)\\]", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let long = "0123456789abcdefghij0123456789abcdefghij0123456789abcdefghij-é-tail";
    let row = match captures(re, "[" + long + "]") {
        Result::Ok(Option::Some(v)) => v,
        Result::Ok(Option::None) => panic "expected a match",
        Result::Err(_) => panic "captures",
    };
    assert!(row[1] == long);
}

test("unset optional group is empty") {
    let re = match compile("(a)?(b)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let row = match captures(re, "b") {
        Result::Ok(Option::Some(v)) => v,
        Result::Ok(Option::None) => panic "expected a match",
        Result::Err(_) => panic "captures",
    };
    assert!(row[1] == "");
    assert!(row[2] == "b");
}

test("replace_all named group") {
    let re = match compile("(?<k>\\w+)=(?<v>\\d+)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let out = match replace_all(re, "a=1 bb=22", "${v}:${k}") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "replace_all",
    };
    assert!(out == "1:a 22:bb");
}

test("unset group captures as empty") {
    let re = match compile("(a)|(b)", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    let row = match captures(re, "b") {
        Result::Ok(Option::Some(v)) => v,
        Result::Ok(Option::None) => panic "expected a match",
        Result::Err(_) => panic "captures",
    };
    assert!(row.len() == 3);
    assert!(row[1] == "");
    assert!(row[2] == "b");
}
