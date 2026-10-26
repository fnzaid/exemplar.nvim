local util = require("exemplar.util")
local M = {}

function M.detect(_)
  local roots = {}
  roots[#roots + 1] = { path = vim.env.VIMRUNTIME .. "/lua", kind = "std" }
  local data = vim.fn.stdpath("data")
  for _, p in ipairs({ data .. "/lazy", data .. "/site/pack/core/opt", data .. "/site/pack/plugins/start", data .. "/site/pack/plugins/opt" }) do
    if util.isdir(p) then roots[#roots + 1] = { path = p, kind = "package" } end
  end
  return roots, {}
end

return M
