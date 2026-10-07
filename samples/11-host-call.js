// title: Native host call
// expect-console: ping
// expect-console: todaklop
// expect-console: POLKADOT
// expect: undefined
console.log(await host.echo("ping"));
console.log(await host.reverse("polkadot"));
console.log(host.uppercase("polkadot"));
