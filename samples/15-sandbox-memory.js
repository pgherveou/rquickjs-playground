// title: Sandbox: memory limit
// expect-error: out of memory
const chunks = [];
while (true) {
  chunks.push(new Array(1_000_000).fill(0));
}
