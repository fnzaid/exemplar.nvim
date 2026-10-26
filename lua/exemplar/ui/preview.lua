local context = require("exemplar.context")

local M = {}

local ns = vim.api.nvim_create_namespace("exemplar.preview")

vim.api.nvim_set_hl(0, "ExemplarHit", { default = true, link = "Search" })
vim.api.nvim_set_hl(0, "ExemplarSignature", { default = true, link = "Title" })
vim.api.nvim_set_hl(0, "ExemplarKind", { default = true, link = "Comment" })
vim.api.nvim_set_hl(0, "ExemplarPath", { default = true, link = "Directory" })
vim.api.nvim_set_hl(0, "ExemplarDef", { default = true, link = "DiagnosticHint" })

--- Fill `buf` with the block for `hit`. Returns the row of the hit line
--- and the first line of the enclosing block, if any.
function M.render(buf, hit)
  local block = context.block(hit)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not block then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Could not read " .. hit.path })
    vim.bo[buf].modifiable = false
    return 1, nil
  end
  local lines = {}
  local offset = 0
  if block.signature then
    lines[1] = block.signature
    lines[2] = "    ..."
    offset = 2
  end
  for _, l in ipairs(block.lines) do lines[#lines + 1] = l end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  pcall(vim.treesitter.stop, buf)
  local started = block.lang and pcall(vim.treesitter.start, buf, block.lang)
  if not started then
    vim.bo[buf].syntax = block.ft or ""
  end

  if block.signature then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = "ExemplarSignature" })
  end
  local row = block.hit_row + offset
  vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = "ExemplarHit", priority = 200 })
  local head = block.signature or (block.lines[1] ~= block.lines[block.hit_row] and block.head) or nil
  return row, head and vim.trim(head) or nil
end

function M.scratch()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  return buf
end

return M
