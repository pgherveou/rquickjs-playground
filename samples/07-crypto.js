// title: Web Crypto
// expect: 16 true ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
const random = crypto.getRandomValues(new Uint8Array(16));
const uuid = crypto.randomUUID();
const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("abc"));
const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
`${random.length} ${/^[0-9a-f-]{36}$/.test(uuid)} ${hex}`
