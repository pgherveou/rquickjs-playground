// title: Sandbox: interval never cleared
// expect-error: time budget
setInterval(() => {}, 10);
"returned"
