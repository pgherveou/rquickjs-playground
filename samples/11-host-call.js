// title: Native host call
// expect: true ping todaklop POLKADOT not a function
const echoed = host.echo("ping");
const reversed = host.reverse("polkadot");
const shouted = host.uppercase("polkadot");
let failure;
try {
  host.missing("");
} catch (error) {
  failure = error.message;
}
`${echoed instanceof Promise} ${await echoed} ${await reversed} ${shouted} ${failure}`
