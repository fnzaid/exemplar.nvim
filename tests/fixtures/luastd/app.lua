local util = require("util.greet")

local function welcome(user)
  -- greet is called with the display name
  local line = util.greet(user.display_name, user.is_admin)
  print(line)
  return line
end

local function banner(users)
  local out = {}
  for _, u in ipairs(users) do
    out[#out + 1] = util.greet(u.name)
  end
  return table.concat(out, "\n")
end

return { welcome = welcome, banner = banner }
