fn main() {
    let board = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    println!("cargo:rustc-link-search={board}");
    println!("cargo:rustc-link-arg=-Tlink.x");
    println!("cargo:rustc-link-arg-tests=-Tembedded-test.x");
    println!("cargo:rerun-if-changed=memory.x");
}
