// title: Native host call
// expect: true ping todaklop POLKADOT not a function
const isAsync = host.echo("ping") instanceof Promise;
const echoed = await host.echo("ping");
const reversed = await host.reverse("polkadot");
const shouted = host.uppercase("polkadot");
let failure;
try {
  host.missing("");
} catch (error) {
  failure = error.message;
}
`${isAsync} ${echoed} ${reversed} ${shouted} ${failure}`
