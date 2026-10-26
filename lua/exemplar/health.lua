local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local info = vim.health.info or vim.health.report_info

function M.check()
  start("exemplar.nvim")
  if vim.fn.has("nvim-0.10") ~= 1 then
    warn("Neovim 0.10 or newer is required.")
  else
    ok("Neovim " .. tostring(vim.version()))
  end

  start("search backend")
  local found = {}
  for _, t in ipairs({ "rg", "git", "grep" }) do
    if vim.fn.executable(t) == 1 then found[#found + 1] = t end
  end
  if #found == 0 then
    warn("None of ripgrep, git or grep is installed. Install ripgrep.")
  else
    ok(("using %s (found: %s)"):format(require("exemplar.search").backend(), table.concat(found, ", ")))
  end

  for _, lang in ipairs({ "zig", "rust", "go", "javascript", "python", "c", "lua" }) do
    start("roots: " .. lang)
    local rs, notes = require("exemplar.roots").get(lang, nil, true)
    local n = 0
    for _, r in ipairs(rs) do
      if r.kind ~= "project" then n = n + 1; info(("%-8s %s"):format(r.kind, r.path)) end
    end
    for _, note in ipairs(notes) do warn(note) end
    if n == 0 and #notes == 0 then
      info("only the current project")
    elseif n > 0 then
      ok(("%d root(s) besides the project"):format(n))
    end
  end
end

return M
