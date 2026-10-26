-- Search backends. Each returns hits shaped like:
--   { path = "/abs/file", lnum = 12, col = 5, text = "the line" }
local config = require("exemplar.config")
local util = require("exemplar.util")

local M = {}

function M.backend()
  local want = config.options.backend
  if want ~= "auto" then
    if vim.fn.executable(want == "git" and "git" or want) == 1 then return want end
    util.notify_once("backend-missing", ("backend = \"%s\" is set but it is not installed. Using what is available."):format(want), vim.log.levels.WARN)
  end
  if vim.fn.executable("rg") == 1 then return "rg" end
  if vim.fn.executable("git") == 1 then
    util.notify_once("rg-fallback", "ripgrep is not installed, so I am using `git grep`. Searches are slower and roots outside git repositories are skipped. Install ripgrep to search everything.")
    return "git"
  end
  util.notify_once("grep-fallback", "Neither ripgrep nor git is installed, so I am using `grep`. Searches are slower. Install ripgrep.")
  return "grep"
end

--- Build the pattern for a symbol. Words get a word-boundary match; a
--- symbol that starts with a non-word character (Zig's @builtins) gets a
--- regex with a trailing boundary instead, because `-w` would reject it.
function M.pattern(word)
  if word:match("^[%w_]") then
    return { text = word, fixed = true, word = true }
  end
  return { text = vim.fn.escape(word, "\\.*+?()[]{}|^$") .. "\\b", fixed = false, word = false }
end

--- Run a search.
---@param spec { word: string, lang: string, roots: table[] }
---@param cb fun(hits: table[], err: string|nil, partial: boolean)
---@return table handle with :kill()
function M.run(spec, cb)
  local name = M.backend()
  local impl = require("exemplar.search." .. name)
  local paths = {}
  for _, r in ipairs(spec.roots) do paths[#paths + 1] = r.path end
  return impl.run({
    pattern = M.pattern(spec.word),
    globs = util.globs[spec.lang] or {},
    paths = paths,
    per_file = config.options.per_file,
    max_hits = config.options.max_hits,
  }, cb)
end

return M
