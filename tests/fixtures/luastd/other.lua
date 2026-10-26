local greet = require("util.greet").greet

local function shout(name)
  return greet(name, true)
end

local function whisper(name)
  return greet(name, false):lower()
end

return { shout = shout, whisper = whisper }

local label = "please greet the user"
local function later(name) return name end -- greet them later
