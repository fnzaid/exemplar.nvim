local util = require("exemplar.util")
local M = {}

function M.detect(_)
  local roots, notes = {}, {}
  local out, err = util.run({ "go", "env", "GOROOT", "GOMODCACHE" })
  if not out then
    notes[#notes + 1] = ("I ran `go env` and it failed: %s. Install Go, or set roots.go in setup()."):format(err)
    return roots, notes
  end
  local lines = vim.split(vim.trim(out), "\n")
  if lines[1] and lines[1] ~= "" then roots[#roots + 1] = { path = lines[1] .. "/src", kind = "std" } end
  if lines[2] and lines[2] ~= "" then roots[#roots + 1] = { path = lines[2], kind = "package" } end
  return roots, notes
end

return M
