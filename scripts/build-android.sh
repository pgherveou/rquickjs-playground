#!/usr/bin/env bash
# Builds the Rust sandbox for Android and generates the Kotlin bindings the demo app compiles against.
# Needs ANDROID_NDK_HOME and the aarch64-linux-android Rust target.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an NDK install}"
min_sdk=26
toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
jni_libs=android/app/src/main/jniLibs/arm64-v8a
bindings=android/app/src/generated/kotlin

export CC_aarch64_linux_android="$toolchain/bin/aarch64-linux-android$min_sdk-clang"
export AR_aarch64_linux_android="$toolchain/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC_aarch64_linux_android"
# rquickjs runs bindgen for Android; clang needs the NDK sysroot to find the C headers.
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$toolchain/sysroot"
cargo build --release --lib --target aarch64-linux-android

cargo build --lib
rm -rf "$jni_libs" "$bindings"
mkdir -p "$jni_libs"
cp target/aarch64-linux-android/release/libplayground.so "$jni_libs/"
cargo run --quiet --bin uniffi-bindgen -- generate \
  --library target/debug/libplayground.dylib \
  --language kotlin --no-format \
  --out-dir "$bindings"
