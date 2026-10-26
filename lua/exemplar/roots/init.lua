-- Search roots per language, detected by asking the toolchain. Cached per
-- language and project.
local util = require("exemplar.util")
local config = require("exemplar.config")

local M = {}

local cache = {}

local weights = { std = 30, compiler = 25, package = 20, project = 10 }

local function norm(entry, default_kind)
  if type(entry) == "string" then entry = { path = entry } end
  entry.kind = entry.kind or default_kind or "package"
  entry.path = util.expand(entry.path)
  entry.weight = weights[entry.kind] or 10
  return entry
end

local function project_root(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local start = file ~= "" and vim.fs.dirname(file) or vim.uv.cwd()
  return vim.fs.root(start, { ".git" }) or vim.uv.cwd()
end

--- Detect roots for a language.
---@param lang string
---@param buf integer|nil
---@param refresh boolean|nil
---@return table[] roots, string[] notes
function M.get(lang, buf, refresh)
  buf = buf or vim.api.nvim_get_current_buf()
  local proj = project_root(buf)
  local key = lang .. "\0" .. proj
  if cache[key] and not refresh then return cache[key].roots, cache[key].notes end

  local roots, notes = {}, {}
  local ok, det = pcall(require, "exemplar.roots." .. lang)
  if ok and type(det) == "table" and det.detect then
    local found, dnotes = det.detect({ buf = buf, project = proj, opts = config.options.languages[lang] or {} })
    for _, r in ipairs(found or {}) do roots[#roots + 1] = norm(r) end
    for _, n in ipairs(dnotes or {}) do notes[#notes + 1] = n end
  else
    notes[#notes + 1] = ("No detector for %s. Set roots.%s in setup() to search anything."):format(lang, lang)
  end

  local user = config.options.roots[lang]
  if user then
    if user.only then roots = {} end
    for _, r in ipairs(user) do roots[#roots + 1] = norm(r) end
  end

  if config.options.project_config then
    local f = proj .. "/.exemplar.lua"
    if vim.uv.fs_stat(f) then
      local okp, pc = pcall(dofile, f)
      if okp and type(pc) == "table" and pc.roots and pc.roots[lang] then
        for _, r in ipairs(pc.roots[lang]) do roots[#roots + 1] = norm(r) end
      elseif not okp then
        notes[#notes + 1] = (".exemplar.lua failed to load: %s"):format(pc)
      end
    end
  end

  roots[#roots + 1] = norm({ path = proj, kind = "project" })

  -- drop missing and duplicate paths, keep order
  local seen, out = {}, {}
  for _, r in ipairs(roots) do
    if util.isdir(r.path) and not seen[r.path] then
      seen[r.path] = true
      out[#out + 1] = r
    elseif not util.isdir(r.path) then
      notes[#notes + 1] = ("Skipped %s: not a directory."):format(r.path)
    end
  end

  cache[key] = { roots = out, notes = notes }
  return out, notes
end

function M.clear()
  cache = {}
end

--- Kind of the root a file lives in.
function M.kind_of(path, roots)
  local best, best_len = nil, -1
  for _, r in ipairs(roots) do
    if path:sub(1, #r.path) == r.path and #r.path > best_len then
      best, best_len = r, #r.path
    end
  end
  return best and best.kind or "project", best and best.weight or 10
end

return M
