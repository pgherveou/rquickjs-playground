// title: TrUAPI stand-in: calls run concurrently
// expect-console: timer fired while both calls were pending
// expect: a b, resolved together
const started = Date.now();
setTimeout(() => console.log("timer fired while both calls were pending"), 20);
const results = await Promise.all([host.call("delay", "100:a"), host.call("delay", "100:b")]);
const elapsed = Date.now() - started;
`${results.join(" ")}, ${elapsed < 180 ? "resolved together" : `took ${elapsed} ms`}`
