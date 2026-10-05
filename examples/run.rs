//! Runs one script file in the sandbox and prints the outcome: `cargo run --example run -- samples/01-arithmetic.js`.

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let path = std::env::args().nth(1).expect("usage: run <script.js>");
    let source = std::fs::read_to_string(&path).expect("read script");
    println!("{:#?}", playground::run_script(source).await);
}
