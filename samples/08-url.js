// title: URL parsing
// expect: example.com 8080 /a/b x=1
const url = new URL("https://example.com:8080/a/b?x=1#frag");
`${url.hostname} ${url.port} ${url.pathname} x=${url.searchParams.get("x")}`
