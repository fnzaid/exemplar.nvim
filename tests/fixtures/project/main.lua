local util = require("util.greet")
print(util.greet("world"))

local function greetEveryone(users)
  for _, u in ipairs(users) do print(util.greet(u)) end
end

return greetEveryone
