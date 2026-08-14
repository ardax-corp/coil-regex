use regex::{compile, captures, replace_all};

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
