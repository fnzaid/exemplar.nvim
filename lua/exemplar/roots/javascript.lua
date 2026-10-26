local util = require("exemplar.util")
local M = {}

function M.detect(ctx)
  local roots, notes = {}, {}
  local file = vim.api.nvim_buf_get_name(ctx.buf)
  local start = file ~= "" and vim.fs.dirname(file) or ctx.project
  local found = vim.fs.find("node_modules", { upward = true, path = start, type = "directory", limit = 1 })
  if found[1] then
    roots[#roots + 1] = { path = found[1], kind = "package" }
  else
    notes[#notes + 1] = "No node_modules above this file. Run your package manager's install, or set roots.javascript in setup()."
  end
  if ctx.opts.global ~= false then
    local out, err = util.run({ "npm", "root", "-g" })
    if out and util.isdir(vim.trim(out)) then
      roots[#roots + 1] = { path = vim.trim(out), kind = "package" }
    elseif err then
      notes[#notes + 1] = ("`npm root -g` failed with \"%s\". Global packages are not searched."):format(err)
    end
  end
  return roots, notes
end

return M
