-- Index of names the library declares, per language and set of roots.
-- Built once per session with one ripgrep run and kept in memory.
local util = require("exemplar.util")
local search = require("exemplar.search")

local M = {}

-- Regexes that match a declaration and leave the name as the last word.
local defs = {
  lua = { [[\bfunction\s+[A-Za-z_][A-Za-z0-9_.:]*]], [[\blocal\s+(function\s+)?[A-Za-z_][A-Za-z0-9_]*]] },
  zig = { [[\b(fn|const|var)\s+[A-Za-z_][A-Za-z0-9_]*]] },
  rust = { [[\b(fn|struct|enum|trait|type|const|static|mod)\s+[A-Za-z_][A-Za-z0-9_]*]] },
  go = { [[\bfunc\s+(\([^)]*\)\s*)?[A-Za-z_][A-Za-z0-9_]*]], [[\b(type|var|const)\s+[A-Za-z_][A-Za-z0-9_]*]] },
  python = { [[\b(def|class)\s+[A-Za-z_][A-Za-z0-9_]*]] },
  javascript = { [[\b(function|class|const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*]] },
  c = { [[^[A-Za-z_][A-Za-z0-9_ \t\*]*[ \t\*]([A-Za-z_][A-Za-z0-9_]*)\s*\(]], [[\b(struct|enum|union)\s+[A-Za-z_][A-Za-z0-9_]*]] },
}

local cache = {}

--- Split camelCase, PascalCase and snake_case into lowercase words.
function M.words(name)
  local out = {}
  local spaced = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u+)(%u%l)", "%1 %2"):gsub("[_%$]+", " ")
  for w in spaced:lower():gmatch("%a+") do out[#out + 1] = w end
  return out
end

local function key_of(lang, paths)
  return lang .. "\0" .. table.concat(paths, ";")
end

--- Build or fetch the index. cb(index) where index = { names = {name = count},
--- idf = {word = weight}, total = n } or nil with a message.
function M.get(lang, paths, cb)
  local regs = defs[lang]
  if not regs then cb(nil, "no declaration patterns for " .. lang) return end
  local key = key_of(lang, paths)
  if cache[key] then cb(cache[key]) return end

  local args
  if search.backend() == "rg" then
    args = { "rg", "-o", "-N", "--no-filename", "--no-messages", "--max-count", "400", "--max-filesize", "2M" }
    for _, g in ipairs(util.globs[lang] or {}) do args[#args + 1] = "-g"; args[#args + 1] = g end
    for _, r in ipairs(regs) do args[#args + 1] = "-e"; args[#args + 1] = r end
  else
    args = { "grep", "-rhoE", "--no-messages" }
    for _, g in ipairs(util.globs[lang] or {}) do args[#args + 1] = "--include=" .. g end
    for _, r in ipairs(regs) do args[#args + 1] = "-e"; args[#args + 1] = r end
  end
  for _, p in ipairs(paths) do args[#args + 1] = p end

  vim.system(args, { text = true }, function(res)
    if res.code ~= 0 and res.code ~= 1 then
      cb(nil, "indexing the library failed: " .. vim.trim(res.stderr or ""))
      return
    end
    local names, total = {}, 0
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      local name = line:match("([%a_%$][%w_%$]*)%s*%(?%s*$") or line:match("([%a_%$][%w_%$]*)$")
      if name and #name >= 2 then
        names[name] = (names[name] or 0) + 1
        total = total + 1
      end
    end
    -- idf: words that appear in few names carry more meaning
    local df, distinct = {}, 0
    for name in pairs(names) do
      distinct = distinct + 1
      local seen = {}
      for _, w in ipairs(M.words(name)) do
        if not seen[w] then seen[w] = true; df[w] = (df[w] or 0) + 1 end
      end
    end
    local idf = {}
    for w, n in pairs(df) do idf[w] = math.log(1 + distinct / n) end
    local index = { names = names, idf = idf, total = total, distinct = distinct }
    cache[key] = index
    cb(index)
  end)
end

function M.clear()
  cache = {}
end

return M
