// title: TextEncoder and TextDecoder
// expect: 6 bytes, héllo
const bytes = new TextEncoder().encode("héllo");
`${bytes.length} bytes, ${new TextDecoder().decode(bytes)}`
