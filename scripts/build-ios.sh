#!/usr/bin/env bash
# Builds the Rust sandbox for iOS and generates the Swift bindings the demo app compiles against.
# Usage: scripts/build-ios.sh [--device]   (simulator only unless --device is given)
set -euo pipefail

cd "$(dirname "$0")/.."
generated=ios/Generated
targets=(aarch64-apple-ios-sim)
if [[ "${1:-}" == "--device" ]]; then
  targets+=(aarch64-apple-ios)
fi

# Must match IPHONEOS_DEPLOYMENT_TARGET in the Xcode project, or the linker warns about every C object.
export IPHONEOS_DEPLOYMENT_TARGET=18.0

# rquickjs runs bindgen for iOS; clang needs the Apple spelling of the simulator triple and an SDK.
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_ios_sim="--target=arm64-apple-ios-simulator -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path)"
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_apple_ios="-isysroot $(xcrun --sdk iphoneos --show-sdk-path)"
for target in "${targets[@]}"; do
  cargo build --release --lib --target "$target"
done

cargo build --lib
rm -rf "$generated"
mkdir -p "$generated/Sources" "$generated/headers"
cargo run --quiet --bin uniffi-bindgen -- generate \
  --library target/debug/libplayground.dylib \
  --language swift \
  --out-dir "$generated/bindings"
mv "$generated/bindings/playground.swift" "$generated/Sources/"
mv "$generated/bindings/playgroundFFI.h" "$generated/headers/"
mv "$generated/bindings/playgroundFFI.modulemap" "$generated/headers/module.modulemap"
rm -rf "$generated/bindings"

libraries=()
for target in "${targets[@]}"; do
  libraries+=(-library "target/$target/release/libplayground.a" -headers "$generated/headers")
done
xcodebuild -create-xcframework "${libraries[@]}" -output "$generated/PlaygroundCore.xcframework"
rm -rf "$generated/headers"
