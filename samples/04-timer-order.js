// title: Timer ordering
// expect: sync, microtask, timeout 0, timeout 20
const order = [];
setTimeout(() => order.push("timeout 20"), 20);
setTimeout(() => order.push("timeout 0"), 0);
queueMicrotask(() => order.push("microtask"));
order.push("sync");
await new Promise((resolve) => setTimeout(resolve, 40));
order.join(", ")
