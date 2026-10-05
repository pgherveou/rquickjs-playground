// title: Console capture
// expect-console: hello [ 1, 2, 3 ] null 2n
// expect-console: [warn] careful
// expect: done
console.log("hello", [1, 2, 3], null, 2n);
console.warn("careful");
"done"
