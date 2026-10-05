// title: btoa and atob
// expect: cG9sa2Fkb3Q= polkadot
const encoded = btoa("polkadot");
`${encoded} ${atob(encoded)}`
