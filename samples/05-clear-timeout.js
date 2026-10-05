// title: clearTimeout
// expect: cleared
const id = setTimeout(() => console.log("never printed"), 5000);
clearTimeout(id);
"cleared"
