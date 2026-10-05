// title: Sandbox: no fetch, require, process or WebAssembly
// expect: undefined undefined undefined undefined
[typeof fetch, typeof require, typeof process, typeof WebAssembly].join(" ")
