local util = require("exemplar.util")
local M = {}

function M.detect(ctx)
  local roots, notes = {}, {}
  local cc = ctx.opts.compiler or (vim.fn.executable("cc") == 1 and "cc" or (vim.fn.executable("clang") == 1 and "clang" or "gcc"))
  if vim.fn.executable(cc) == 1 then
    local ok, proc = pcall(vim.system, { cc, "-E", "-Wp,-v", "-xc", "/dev/null" }, { text = true })
    if ok then
      local res = proc:wait(4000)
      local inside = false
      for line in (res.stderr or ""):gmatch("[^\n]+") do
        if line:find("search starts here") then inside = true
        elseif line:find("End of search list") then inside = false
        elseif inside then
          local p = vim.trim(line)
          if util.isdir(p) then roots[#roots + 1] = { path = p, kind = "std" } end
        end
      end
    end
  else
    notes[#notes + 1] = "No C compiler found (cc, clang, gcc). System headers are not searched. Set roots.c in setup() to add include directories."
  end
  for _, p in ipairs({ "/usr/include", "/usr/local/include" }) do
    if util.isdir(p) then roots[#roots + 1] = { path = p, kind = "std" } end
  end
  return roots, notes
end

return M
