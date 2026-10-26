-- Scoring. The weights are a starting point; tune them here.
local util = require("exemplar.util")
local roots = require("exemplar.roots")
local config = require("exemplar.config")

local M = {}

M.weights = {
  chain = 15,        -- line contains the full dotted chain
  call = 10,         -- symbol is followed by "("
  ts_call = 5,       -- treesitter confirms a call
  definition = -20,  -- kept, tagged
  test_path = -8,
  long_line = -10,
  same_file = -15,   -- second hit from one file
  same_dir = -10,    -- third or later hit from one directory
}

local function is_comment_only(text, lang)
  local prefix = util.comment_prefix[lang]
  if not prefix then return false end
  local s = text:match("^%s*(.*)$")
  return s:sub(1, #prefix) == prefix
end

local function is_definition(text, lang, word)
  for _, pat in ipairs(util.definition_patterns(lang, word)) do
    if text:find(pat) then return true end
  end
  return false
end

---@param hits table[]
---@param ctx { word: string, chain: string|nil, lang: string, roots: table[] }
---@return table[] ranked, hits with .score, .kind, .definition
function M.rank(hits, ctx)
  local opts = config.options
  local out = {}
  local seen = {}
  local word_call = vim.pesc(ctx.word) .. "%s*%("
  for _, h in ipairs(hits) do
    local trimmed = vim.trim(h.text)
    -- the same line in many files (an import, a boilerplate call) is one example, not ten
    if not is_comment_only(h.text, ctx.lang) and not seen[trimmed] then
      seen[trimmed] = true
      local kind, weight = roots.kind_of(h.path, ctx.roots)
      local score = weight
      h.kind = kind
      h.definition = is_definition(h.text, ctx.lang, ctx.word)
      if h.definition then
        if not opts.show_definitions then goto continue end
        score = score + M.weights.definition
      end
      if ctx.chain and h.text:find(ctx.chain, 1, true) then score = score + M.weights.chain end
      if h.text:find(word_call) then score = score + M.weights.call end
      if h.path:lower():find("test") then score = score + M.weights.test_path end
      if #h.text > 160 then score = score + M.weights.long_line end
      h.score = score
      out[#out + 1] = h
    end
    ::continue::
  end

  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.path ~= b.path then return a.path < b.path end
    return a.lnum < b.lnum
  end)

  if not opts.diverse then return out end

  -- Diversity: penalise repeats, then re-sort. Hits are never dropped,
  -- they move down, so "show more" still reaches them.
  local per_file, per_dir = {}, {}
  for _, h in ipairs(out) do
    local dir = vim.fs.dirname(h.path)
    per_file[h.path] = (per_file[h.path] or 0) + 1
    per_dir[dir] = (per_dir[dir] or 0) + 1
    if per_file[h.path] > 2 then h.score = h.score + M.weights.same_file * (per_file[h.path] - 2) end
    if per_dir[dir] > 4 then h.score = h.score + M.weights.same_dir * (per_dir[dir] - 4) end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.path ~= b.path then return a.path < b.path end
    return a.lnum < b.lnum
  end)
  return out
end

return M
