if vim.g.loaded_exemplar then return end
vim.g.loaded_exemplar = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("exemplar.nvim needs Neovim 0.10 or newer.", vim.log.levels.ERROR)
  return
end

local sub = { "names", "next", "prev", "roots", "qf", "refresh" }

vim.api.nvim_create_user_command("Exemplar", function(cmd)
  local ex = require("exemplar")
  local a = cmd.fargs
  if a[1] == "names" then
    if a[2] == "clear" then require("exemplar.names").clear() else require("exemplar.names").run() end
  elseif a[1] == "next" then ex.next(tonumber(a[2]) or 1)
  elseif a[1] == "prev" then ex.prev(tonumber(a[2]) or 1)
  elseif a[1] == "qf" then ex.quickfix()
  elseif a[1] == "refresh" then ex.clear_cache(); vim.notify("exemplar: cache cleared", vim.log.levels.INFO)
  elseif a[1] == "roots" then
    local rs, notes = ex.roots(a[2], a[3] == "refresh" or a[2] == "refresh")
    local lines = {}
    for _, r in ipairs(rs) do lines[#lines + 1] = ("%-8s %s"):format(r.kind, r.path) end
    for _, n in ipairs(notes) do lines[#lines + 1] = "note: " .. n end
    if #lines == 0 then lines[1] = "no roots" end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "exemplar roots" })
  elseif cmd.range > 0 and #a == 0 then
    local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
    local text = ok and vim.trim(table.concat(region, " ")) or ""
    if text == "" then vim.notify("exemplar: the selection is empty.", vim.log.levels.WARN) return end
    ex.show(text)
  else
    ex.show(table.concat(a, " "))
  end
end, {
  nargs = "*",
  range = true,
  complete = function(lead, line)
    if line:match("^%s*Exemplar%s+%S+%s") then return {} end
    return vim.tbl_filter(function(s) return s:find(lead, 1, true) == 1 end, sub)
  end,
  desc = "exemplar.nvim: show examples of the symbol under the cursor",
})
