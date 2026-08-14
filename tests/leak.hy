use gc::{collect};
use regex::{compile};

test("compile and drop does not leak across collect") {
    let i = 0;
    while i < 32 {
        let _re = match compile("a+", "") {
            Result::Ok(v) => v,
            Result::Err(_) => panic "compile",
        };
        i = i + 1;
    }
    collect();
    assert(true)?;
}
