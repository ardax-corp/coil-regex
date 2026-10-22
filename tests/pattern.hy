use tests::assert;
use text::{Searchable, Span};
use regex::{Regex, compile};

fn re(string pattern) -> Regex {
    return match compile(pattern, "") {
        Result::Ok(r) => r,
        Result::Err(_) => panic "compile",
    };
}

test("a Regex searches strings through Searchable") {
    assert!("foobar".contains(re("o+b")));
    assert!(!"foobar".contains(re("z+")));
    let at = "ab123cd".find(re("[0-9]+")) ?? new Span(-1, -1);
    assert!(at.start == 2 && at.end == 5);
    assert!("ab123cd".find(re("x")).is_none());
    assert!("a1b22c333".find_all(re("[0-9]+")).len() == 3);
}

test("anchored prefix and suffix") {
    assert!("2026-10-22".starts_with(re("[0-9]{4}-")));
    assert!(!"v2026".starts_with(re("[0-9]+")));
    assert!("main.hy".ends_with(re("\\.h[a-z]")));
    // The leftmost match ends early, a later one ends at the end.
    assert!("xab".ends_with(re("a|ab")));
    assert!(!"abx".ends_with(re("a|ab")));
}

test("split and replace with captures") {
    let parts = "a, b,c ,  d".split(re("\\s*,\\s*"));
    assert!(parts.len() == 4);
    assert!(parts[0] == "a" && parts[3] == "d");
    let (k, v) = "key = value".split_once(re("\\s*=\\s*")) ?? ("", "");
    assert!(k == "key" && v == "value");
    assert!("a=1 b=2".replace_all(re("(\\w)=(\\d)"), "$2:$1") == "1:a 2:b");
    assert!("a=1 b=2".replace_first(re("(?<k>\\w)=(\\d)"), "${k}") == "a b=2");
}

test("empty matches step over whole characters") {
    assert!("é!".replace_all(re("x*"), "|") == "|é|!|");
    assert!("ab".split(re("")).len() == 4);
}
