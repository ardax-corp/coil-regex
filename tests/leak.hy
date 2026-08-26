use gc::{collect, heap_bytes};
use regex::{compile};

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

test("Regex.drop zeros handle") {
    let re = match compile("a+", "") {
        Result::Ok(v) => v,
        Result::Err(_) => panic "compile",
    };
    re.drop();
    assert(re.handle == 0)?;
    re.drop();
    assert(re.handle == 0)?;
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
