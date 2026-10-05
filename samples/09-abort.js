// title: AbortController
// expect-console: abort event
// expect: true stop
const controller = new AbortController();
controller.signal.addEventListener("abort", () => console.log("abort event"));
controller.abort("stop");
`${controller.signal.aborted} ${controller.signal.reason}`
