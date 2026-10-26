local M = {}

--- Say hello to someone.
function M.greet(name, loud)
  local msg = "hello " .. name
  if loud then msg = msg:upper() end
  return msg
end

return M
