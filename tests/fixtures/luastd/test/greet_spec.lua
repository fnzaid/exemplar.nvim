local util = require("util.greet")
assert(util.greet("x") == "hello x")
assert(util.greet("x", true) == "HELLO X")
