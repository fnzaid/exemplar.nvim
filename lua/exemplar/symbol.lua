-- Word under the cursor and the dotted chain it belongs to.
local M = {}

local chain_types = {
  field_expression = true, member_expression = true, selector_expression = true,
  attribute = true, scoped_identifier = true, dot_index_expression = true,
  qualified_identifier = true, scoped_type_identifier = true, navigation_expression = true,
}

local leaf_types = {
  identifier = true, builtin_identifier = true, property_identifier = true,
  field_identifier = true, type_identifier = true, shorthand_field_identifier = true,
  BUILTINIDENTIFIER = true, IDENTIFIER = true,
}

local function cword_fallback(buf)
  local cw = vim.fn.expand("<cword>")
  if cw == "" then return nil end
  if vim.bo[buf].filetype == "zig" then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local s = line:sub(1, col):find("[%w_@]*$")
    if s and line:sub(s, s) == "@" and not cw:find("^@") then cw = "@" .. cw end
  end
  return { word = cw }
end

---@param buf integer|nil
---@return { word: string, chain: string|nil }|nil
function M.at_cursor(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  -- A buffer that was never highlighted has no tree yet; parse it first.
  local okp, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if okp and parser then pcall(parser.parse, parser, true) end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf })
  if not ok or not node then return cword_fallback(buf) end
  local t = node:type()
  if not (leaf_types[t] or t:find("identifier")) then return cword_fallback(buf) end

  local word = vim.treesitter.get_node_text(node, buf)
  if word == "" then return cword_fallback(buf) end

  local chain = nil
  local p = node:parent()
  local top = nil
  while p and chain_types[p:type()] do
    top = p
    p = p:parent()
  end
  if top then
    chain = vim.treesitter.get_node_text(top, buf):gsub("%s+", "")
    if chain == word then chain = nil end
  end
  return { word = word, chain = chain }
end

return M
