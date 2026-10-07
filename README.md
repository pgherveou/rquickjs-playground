# rquickjs playground

Runs JavaScript in a QuickJS sandbox from Rust, with no WebView, and calls it from a SwiftUI app and a
Jetpack Compose app. Built on [rquickjs](https://github.com/DelSkayn/rquickjs) (QuickJS-NG), a few
[LLRT](https://github.com/awslabs/llrt) modules for web globals, and
[UniFFI](https://github.com/mozilla/uniffi-rs) for the Swift and Kotlin bindings.

| iOS simulator | Android emulator |
| :---: | :---: |
| <img src="docs/ios.gif" width="300" alt="Samples running in the iOS simulator"> | <img src="docs/android.gif" width="300" alt="Samples running in the Android emulator"> |

## Run

```bash
cargo test
```

```bash
scripts/build-ios.sh && open ios/Playground.xcodeproj
```

```bash
scripts/build-android.sh && (cd android && ./gradlew :app:installDebug)
```

`cargo run --example run -- samples/07-crypto.js` runs one script from the command line. Rerun the build
script for a platform after changing `src/`.

- iOS needs the `aarch64-apple-ios-sim` Rust target.
- Android needs the `aarch64-linux-android` Rust target, JDK 17, and the SDK in `ANDROID_HOME` with the
  NDK version pinned in `android/app/build.gradle.kts`. It builds for arm64 devices and emulators only.

## What it does

- `run_script(source, listener, time_budget)` is the one exported function. It is async, runs the script on its own
  thread in a fresh QuickJS runtime, and returns the value or error plus everything the script logged.
  The optional `ConsoleListener`, implemented in Swift or Kotlin, also receives each line as it is logged.
- Limits per run: 16 MiB heap, 1 MiB stack, 1 second for execution and pending timers unless the caller
  passes a longer `time_budget`.
- Globals: `console`, timers, `queueMicrotask`, `crypto` (with `subtle`), `URL`, `TextEncoder`,
  `TextDecoder`, `atob`, `btoa`, `Buffer`, `AbortController`, `EventTarget`, and `host`, a Rust struct
  exposed with rquickjs's class macros: `await host.echo(text)` and `await host.reverse(text)` are
  native async methods, `host.uppercase(text)` a sync one.
- No `fetch`, `require`, `process`, file system, network or `WebAssembly`.
- Both apps also have a "Parallel sandboxes" screen that starts N sandboxes at once (default 10), each
  logging `worker i start`, waiting, then logging `worker i done`. On Android the wait is 200 ms. On iOS
  it is 3 s, and the screen runs the same script in N QuickJS sandboxes, then in N hidden `WKWebView`s,
  and shows side by side the total time, when the last one started, how many ran at once, failures, the
  app's memory growth and the memory of the web views' WebKit processes. The web views stay alive until
  the next Run, so `scripts/measure-memory.sh` can measure the simulator's processes from the Mac.
- `samples/*.js` hold the scripts both apps list. Each header states what it must produce
  (`// expect:`, `// expect-error:`, `// expect-console:`), and `cargo test` checks every one.

## Findings

- `llrt_timers` keeps timers in process-wide state, and freeing a runtime with a timer pending aborts
  the process on a QuickJS leak assertion. It is still that way on llrt `main`. `src/timers.rs`
  replaces it with timers owned by the runtime.
- The published `llrt_*` crates (0.8.1-beta) need `rquickjs ^0.11`, so this depends on llrt's `main`
  branch (0.9.0-beta, rquickjs 0.14), one crate per module. The 0.8.1-beta `llrt_modules` umbrella
  crate did not build without its `path` feature.
- rquickjs's `full` feature includes `dyn-load` (native modules through `dlopen2`), which does not
  compile for iOS or Android: `dlopen2` 0.9.0 uses `once_cell` there without depending on it. The
  sandbox enables only `futures` and `macro`, and has no reason to load native modules anyway.
- rquickjs ships no iOS or Android bindings. Both builds enable its `bindgen` feature: iOS passes
  clang the simulator target and SDK, Android the NDK sysroot (see `scripts/`).
- Size: the iOS simulator debug app is about 12 MB, and the stripped Android arm64 library 6.4 MB.
- QuickJS vs hidden `WKWebView` on the iPhone 17 simulator, 200 ms wait: a QuickJS sandbox costs about
  0.3 MB and 500 of them all start within 40 ms. Each web view gets its own WebContent process of about
  15 MB, and web views start at about 20 per second (100 in 4.5 s, 500 in 23 s).
- WebKit allows about 400 WebContent processes per app. Past that it terminates the extra web views
  (`reason=ExceededProcessCountLimit` in the log): asking for 500 left 100 failed, in two runs. The
  simulator has no memory limit, so this cap is where it breaks; a device may run out of memory first.
- The app reads each web view's WebContent process ID with WebKit's `_webProcessIdentifier` SPI and its
  footprint with `proc_pid_rusage`. On the simulator this matches Apple's `footprint` tool within 1%, and
  it also works on a device. On an iPhone 17e, 10 web views measured 15.5 MB each right after the run, and
  Instruments measured about 7.9 MB each a few minutes later, so idle hidden web views seem to shrink.
