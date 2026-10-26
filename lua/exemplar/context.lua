-- The block shown around a hit: the enclosing function when treesitter can
-- find one, with its first line pinned if the function is long.
local util = require("exemplar.util")
local config = require("exemplar.config")

local M = {}

local function lang_for(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft then return nil, nil end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  return lang, ft
end

local function hit_lang_key(ft)
  if ft == "typescript" or ft == "javascriptreact" or ft == "typescriptreact" then return "javascript" end
  if ft == "cpp" then return "c" end
  return ft
end

local function looks_like_block(t)
  return t:find("function") or t:find("method") or t:find("func") or t:find("^fn_") or t:find("_item$")
      or t == "Decl" or t == "TopLevelDecl" or t == "class_definition" or t == "class_declaration"
      or t == "impl_item" or t == "test_declaration" or t == "TestDecl"
end

--- Find the smallest enclosing function-like node for a line.
local function enclosing(text, lang, lnum)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok or not parser then return nil end
  local okt, trees = pcall(parser.parse, parser)
  if not okt or not trees or not trees[1] then return nil end
  local root = trees[1]:root()
  local node = root:named_descendant_for_range(lnum - 1, 0, lnum - 1, 0)
  while node do
    local t = node:type()
    if looks_like_block(t) then
      local srow, _, erow = node:range()
      if erow > srow then return srow + 1, erow + 1 end
    end
    node = node:parent()
  end
  return nil
end

--- Lines to show for a hit.
---@param hit { path: string, lnum: integer }
---@return { lines: string[], first: integer, hit_row: integer, lang: string|nil, ft: string|nil, signature: string|nil }|nil
function M.block(hit)
  local opts = config.options
  local text = util.readfile(hit.path, 8 * 1024 * 1024)
  if not text then return nil end
  local all = vim.split(text, "\n", { plain = true })
  local lang, ft = lang_for(hit.path)

  local first, last
  if lang and #text <= 512 * 1024 then
    first, last = enclosing(text, lang, hit.lnum)
  end
  local signature
  if first and last and hit.definition then
    -- a definition reads better with the comment block above it
    local prefix = util.comment_prefix[hit_lang_key(ft)]
    if prefix then
      while first > 1 and vim.trim(all[first - 1]):sub(1, #prefix) == prefix do first = first - 1 end
    end
  end
  if first and last then
    if last - first + 1 > opts.max_block then
      signature = all[first]
      local half = math.floor(opts.max_block / 2)
      first = math.max(first + 1, hit.lnum - half)
      last = math.min(last, first + opts.max_block - 1)
    end
  else
    first = math.max(1, hit.lnum - opts.context)
    last = math.min(#all, hit.lnum + opts.context)
  end

  local lines = {}
  for i = first, last do lines[#lines + 1] = all[i] or "" end
  return {
    lines = lines, first = first, hit_row = hit.lnum - first + 1, lang = lang, ft = ft,
    signature = signature, head = (first and last and all[first]) or nil,
  }
end

return M
