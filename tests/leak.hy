use gc::{collect, heap_bytes};
use regex::{RegexError, compile, is_match};

fn compile_batch(int n) {
    let i = 0;
    while i < n {
        let _re = match compile("a+", "") {
            Result::Ok(v) => v,
            Result::Err(_) => panic "compile",
        };
        i = i + 1;
    }
}

test("Regex.drop then is_match is Runtime") {
    let re = match compile("a+", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    re.drop();
    match is_match(re, "aaa") {
        Result::Ok(_) => panic "expected Err after drop",
        Result::Err(e) => match e {
            RegexError::Runtime => {},
            default => panic "expected Runtime",
        },
    };
    re.drop();
    match is_match(re, "aaa") {
        Result::Ok(_) => panic "expected Err after drop",
        Result::Err(e) => match e {
            RegexError::Runtime => {},
            default => panic "expected Runtime",
        },
    };
}

test("compile and drop does not grow heap across collect") {
    compile_batch(32);
    collect();
    let before = heap_bytes();
    compile_batch(32);
    collect();
    let after = heap_bytes();
    assert(after <= before)?;
}
