-- Second pass over the best candidates with treesitter: drop hits inside
-- strings and comments, and recognise real calls. Only the files behind
-- the top candidates are parsed, and only when they are small.
local util = require("exemplar.util")

local M = {}

local MAX_FILE = 512 * 1024

local function lang_for(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft then return nil end
  return vim.treesitter.language.get_lang(ft) or ft
end

--- "comment" | "string" | "call" | "use" | nil when the file cannot be parsed.
local function classify(tree, lnum, col)
  local root = tree:root()
  local node = root:named_descendant_for_range(lnum - 1, col - 1, lnum - 1, col - 1)
  while node do
    local t = node:type()
    if t:find("comment") then return "comment" end
    if t:find("string") then return "string" end
    if t:find("call") or t:find("builtin") then return "call" end
    node = node:parent()
  end
  return "use"
end

--- Refine the first `count` hits in place. Returns the list with dropped
--- hits removed and scores adjusted. Hits past `count` are untouched.
---@param hits table[] ranked
---@param count integer
---@param call_bonus integer
function M.refine(hits, count, call_bonus)
  local trees = {}
  local out = {}
  for i, h in ipairs(hits) do
    local keep = true
    if i <= count then
      local lang = lang_for(h.path)
      if lang then
        local tree = trees[h.path]
        if tree == nil then
          tree = false
          local text = util.readfile(h.path, MAX_FILE)
          if text then
            local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
            if ok and parser then
              local okp, ts = pcall(parser.parse, parser)
              if okp and ts and ts[1] then tree = ts[1] end
            end
          end
          trees[h.path] = tree
        end
        if tree then
          local kind = classify(tree, h.lnum, h.col or 1)
          if kind == "comment" or kind == "string" then
            keep = false
          elseif kind == "call" then
            h.call = true
            h.score = h.score + call_bonus
          end
        end
      end
    end
    if keep then out[#out + 1] = h end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.path ~= b.path then return a.path < b.path end
    return a.lnum < b.lnum
  end)
  return out
end

return M
