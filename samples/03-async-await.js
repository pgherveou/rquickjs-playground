// title: Top-level await
// expect: waited 10ms
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
await wait(10);
"waited 10ms"
