# rquickjs playground

An experiment in running product JavaScript without a WebView: a Rust sandbox on
[rquickjs](https://github.com/DelSkayn/rquickjs) (QuickJS-NG) with a few
[LLRT](https://github.com/awslabs/llrt) modules for web globals, called from a SwiftUI app through
[UniFFI](https://github.com/mozilla/uniffi-rs).

The app lists the scripts in `samples/`. Selecting one shows the script, runs it in a fresh sandbox,
and shows the result, any error, and what it logged.

## Layout

```
src/lib.rs            async run_script(source) -> ScriptOutcome, the only exported function
src/console.rs        console.* that records lines instead of printing them
src/timers.rs         setTimeout / setInterval / clear* / queueMicrotask, owned by one runtime
samples/*.js          sample scripts; the header states what each must produce
tests/samples.rs      runs every sample and checks it against its header
tests/concurrency.rs  one caller thread awaits ten sandboxes at once
examples/run.rs       runs one script from the command line
scripts/build-ios.sh  builds the xcframework and Swift bindings into ios/Generated/
ios/                  SwiftUI app; its project includes samples/ as bundle resources
```

## Run it

```bash
cargo test
```

```bash
cargo run --example run -- samples/07-crypto.js
```

```bash
scripts/build-ios.sh
```

```bash
open ios/Playground.xcodeproj
```

Run `scripts/build-ios.sh` again after changing anything under `src/`. It builds the simulator slice;
pass `--device` to add the device slice. It needs the `aarch64-apple-ios-sim` (and for `--device`,
`aarch64-apple-ios`) Rust targets.

To build and install from the command line instead of Xcode:

```bash
xcodebuild -project ios/Playground.xcodeproj -scheme Playground -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ios/build/DerivedData build
```

## Adding a sample

Drop a `.js` file into `samples/`. The app and the test pick it up from there. Header lines:

- `// title: <text>` names it in the app.
- `// expect: <text>` is the formatted value of the last expression.
- `// expect-error: <text>` must appear in the error instead.
- `// expect-console: <text>` is one logged line, in order. Repeat it for several lines.

Scripts run with top-level `await`, and a run waits for every pending timer.

## The sandbox

Each run gets its own QuickJS runtime on its own thread. `run_script` is async, so the caller's
thread (a Swift concurrency thread in the app) is free while the script runs. Each runtime has a
16 MiB heap limit, a 1 MiB stack limit and a 1 second budget. The budget covers both execution,
through QuickJS's interrupt handler, and waiting on timers.

Globals:

| Global                                                                         | Source               |
| ------------------------------------------------------------------------------ | -------------------- |
| `AbortController`, `AbortSignal` (without `timeout`)                           | `llrt_abort`         |
| `atob`, `btoa`, `Buffer`                                                       | `llrt_buffer`        |
| `crypto` (`getRandomValues`, `randomUUID`, `subtle`)                           | `llrt_crypto`        |
| `EventTarget`, `Event`                                                         | `llrt_events`        |
| `URL`, `URLSearchParams`                                                       | `llrt_url`           |
| `TextEncoder`, `TextDecoder`                                                   | `llrt_util`          |
| `console`                                                                      | `src/console.rs`     |
| `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`, `queueMicrotask` | `src/timers.rs`      |
| `host.call(method, payload)`, a native async function standing in for TrUAPI   | `src/lib.rs`         |

There is no `fetch`, `require`, `process`, file system or network access, and no `WebAssembly`:
QuickJS-NG does not implement it and no LLRT module adds it.

## Findings

- `llrt_modules` 0.8.1-beta depends on `rquickjs ^0.11`, two minor versions behind rquickjs 0.14, so
  the playground pins 0.11.
- The `llrt_modules` umbrella crate does not compile without its `path` feature. The playground
  depends on the individual `llrt_*` crates instead.
- `llrt_timers` keeps every runtime's timers in process-wide state. Freeing a runtime while a timer is
  pending trips QuickJS's leak assertion (`list_empty(&rt->gc_obj_list)`) and aborts the process,
  which is what stopping a worker mid-`setInterval` would do. `src/timers.rs` replaces it with timers
  spawned on the runtime itself. `AbortSignal.timeout` goes through `llrt_timers`, so it is removed.
- rquickjs ships no prebuilt bindings for iOS. The iOS build enables its `bindgen` feature and passes
  clang the Apple simulator triple and the SDK path (see `scripts/build-ios.sh`).
- The C parts of QuickJS follow `IPHONEOS_DEPLOYMENT_TARGET`. Without it they target the SDK version
  and the linker warns on every object.
- `console.log` of an object prints it over several lines (`{\n  a: 1\n}`), unlike Node's `{ a: 1 }`.
- A simulator debug build of the app is about 9 MB with the release Rust library linked in.
