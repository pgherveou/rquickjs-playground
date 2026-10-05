// title: TrUAPI stand-in: host.call
// expect: ping todaklop unknown host method: missing
const echoed = await host.call("echo", "ping");
const reversed = await host.call("reverse", "polkadot");
let failure;
try {
  await host.call("missing", "");
} catch (error) {
  failure = error.message;
}
`${echoed} ${reversed} ${failure}`
