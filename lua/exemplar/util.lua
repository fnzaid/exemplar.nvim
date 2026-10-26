local M = {}

local notified = {}

--- One notification per key per session for fallbacks and other notices.
function M.notify_once(key, msg, level)
  if notified[key] then return end
  notified[key] = true
  vim.schedule(function() vim.notify(msg, level or vim.log.levels.INFO, { title = "exemplar" }) end)
end

function M.notify(msg, level)
  vim.schedule(function() vim.notify(msg, level or vim.log.levels.INFO, { title = "exemplar" }) end)
end

--- Run a command and wait for it. Returns stdout or nil plus a short reason.
---@param cmd string[]
---@param timeout integer|nil ms
---@return string|nil, string|nil
function M.run(cmd, timeout)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return nil, cmd[1] .. ": command not found"
  end
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then return nil, tostring(proc) end
  local res = proc:wait(timeout or 4000)
  if res.code ~= 0 then
    local err = (res.stderr or ""):gsub("%s+$", "")
    if err == "" then err = ("exit code %d"):format(res.code) end
    return nil, err
  end
  return res.stdout or "", nil
end

function M.expand(path)
  return vim.fs.normalize(vim.fn.expand(path))
end

function M.isdir(path)
  return path and vim.fn.isdirectory(path) == 1
end

function M.readfile(path, max_bytes)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  if max_bytes and size > max_bytes then f:close() return nil end
  f:seek("set", 0)
  local text = f:read("*a")
  f:close()
  return text
end

--- Language key for a buffer: filetype with a few merges.
function M.lang_of(buf)
  local ft = vim.bo[buf or 0].filetype
  local map = { typescript = "javascript", typescriptreact = "javascript", javascriptreact = "javascript",
                cpp = "c", objc = "c", sh = nil }
  if map[ft] ~= nil then return map[ft] end
  return ft ~= "" and ft or nil
end

--- File globs searched per language.
M.globs = {
  zig = { "*.zig" },
  rust = { "*.rs" },
  go = { "*.go" },
  javascript = { "*.js", "*.mjs", "*.cjs", "*.ts", "*.tsx", "*.jsx" },
  python = { "*.py", "*.pyi" },
  c = { "*.c", "*.h", "*.cc", "*.cpp", "*.hpp", "*.hh", "*.cxx" },
  lua = { "*.lua" },
}

--- Line-comment prefixes, used to drop comment-only hits.
M.comment_prefix = {
  zig = "//", rust = "//", go = "//", javascript = "//", c = "//", lua = "--", python = "#",
}

--- Patterns that mark a line as a definition of `name`.
function M.definition_patterns(lang, name)
  local n = vim.pesc(name)
  local common = { "fn%s+" .. n .. "%s*%(", "func%s+" .. n .. "%s*%(", "func%s+%([^)]*%)%s*" .. n .. "%s*%(",
                   "def%s+" .. n .. "%s*%(", "function%s+" .. n .. "%s*%(", "function%s+[%w_.:]*[.:]" .. n .. "%s*%(",
                   "^%s*" .. n .. "%s*=%s*function", "const%s+" .. n .. "%s*=", "^%s*pub%s+" .. n .. "%s*=",
                   "class%s+" .. n .. "[%s:({]", "struct%s+" .. n .. "[%s{]", "type%s+" .. n .. "[%s=]" }
  return common
end

return M
