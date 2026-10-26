local config = require("exemplar.config")
local util = require("exemplar.util")
local symbol = require("exemplar.symbol")
local roots = require("exemplar.roots")
local search = require("exemplar.search")
local rank = require("exemplar.rank")
local refine = require("exemplar.refine")

local M = {}

-- The last search: { word, chain, lang, roots, all, results, index, partial }
M.session = nil

local cache = {}
local running = nil
local peek_timer = nil

function M.setup(opts)
  config.setup(opts)
end

local function roots_key(rs)
  local parts = {}
  for _, r in ipairs(rs) do parts[#parts + 1] = r.path end
  return table.concat(parts, ";")
end

--- Search for a symbol. Calls cb(session, err).
---@param sym { word: string, chain: string|nil }
---@param lang string
---@param buf integer|nil
---@param cb fun(session: table|nil, err: string|nil)
function M.search(sym, lang, buf, cb)
  buf = buf or vim.api.nvim_get_current_buf()
  local rs, notes = roots.get(lang, buf)
  for _, n in ipairs(notes) do util.notify_once("roots:" .. n, n, vim.log.levels.WARN) end
  if #rs == 0 then
    cb(nil, ("I have nowhere to search for %s code. `:Exemplar roots` shows why, and roots.%s in setup() fixes it."):format(lang, lang))
    return
  end

  local key = table.concat({ sym.word, lang, search.backend(), roots_key(rs) }, "\0")
  if cache[key] then
    cb(cache[key], nil)
    return
  end

  M.run_search(sym, lang, rs, key, cb, false)
end

--- Narrower name when a short one floods the search: the last two
--- segments of the chain, e.g. "mem.tokenize" for "std.mem.tokenize".
local function narrower(sym)
  if not sym.chain then return nil end
  local a, b = sym.chain:match("([%w_@]+)[.:]([%w_@]+)$")
  if a and b and b == sym.word then return a .. "." .. b end
  return nil
end

function M.run_search(sym, lang, rs, key, cb, narrowed)
  if running then running.kill() end
  local slow = vim.defer_fn(function()
    vim.api.nvim_echo({ { ("exemplar: searching %d places for %s"):format(#rs, sym.word), "Comment" } }, false, {})
  end, 300)
  running = search.run({ word = sym.word, lang = lang, roots = rs }, function(hits, err, partial)
    running = nil
    slow:stop()
    vim.schedule(function()
      vim.api.nvim_echo({ { "" } }, false, {})
      if err then cb(nil, err) return end
      if partial and not narrowed then
        local n = narrower(sym)
        if n then
          M.run_search({ word = n, chain = sym.chain, display = sym.word }, lang, rs, key, cb, true)
          return
        end
      end
      local ranked = rank.rank(hits, { word = sym.word, chain = sym.chain, lang = lang, roots = rs })
      ranked = refine.refine(ranked, config.options.limit * 4, rank.weights.ts_call)
      local hide = not config.options.show_definitions
      local results = {}
      for _, h in ipairs(ranked) do
        if not (hide and h.definition) then results[#results + 1] = h end
      end
      local session = {
        word = sym.display or sym.word, chain = sym.chain, lang = lang, roots = rs,
        all = ranked, results = results, index = 1, partial = partial, hide_definitions = hide,
      }
      cache[key] = session
      cb(session, nil)
    end)
  end)
end

local function describe_roots(rs)
  local kinds = {}
  for _, r in ipairs(rs) do kinds[#kinds + 1] = r.kind end
  return table.concat(kinds, ", ")
end

local function resolve(query, buf)
  local lang = util.lang_of(buf)
  if not lang then
    return nil, nil, "This buffer has no filetype, so I do not know which language's libraries to search. Set the filetype first."
  end
  local sym
  if query and query ~= "" then
    local word = query:match("([%w_@]+)$") or query
    sym = { word = word, chain = query ~= word and query or nil }
  else
    sym = symbol.at_cursor(buf)
  end
  if not sym then return nil, nil, "There is no word under the cursor." end
  return sym, lang, nil
end

--- Search and open the list.
---@param query string|nil defaults to the symbol under the cursor
function M.show(query)
  local buf = vim.api.nvim_get_current_buf()
  local sym, lang, err = resolve(query, buf)
  if err then util.notify(err, vim.log.levels.WARN) return end
  M.search(sym, lang, buf, function(session, serr)
    if serr then util.notify(serr, vim.log.levels.ERROR) return end
    M.session = session
    if #session.results == 0 then
      local hint = sym.chain and "" or " Try the full name if it has one."
      util.notify(("No uses of `%s` in %d roots (%s). `:Exemplar roots` lists them.%s"):format(sym.word, #session.roots, describe_roots(session.roots), hint), vim.log.levels.WARN)
      return
    end
    if session.partial then
      util.notify(("Showing the best %d of the first %d hits for `%s`. The search stopped early. A longer name gives better results."):format(config.options.limit, config.options.max_hits, sym.word), vim.log.levels.INFO)
    end
    if config.options.picker == "snacks" then
      local ok, snacks = pcall(require, "snacks")
      if ok and snacks.picker then
        local items = {}
        for i, h in ipairs(session.results) do
          items[i] = { file = h.path, pos = { h.lnum, (h.col or 1) - 1 }, text = vim.trim(h.text), kind = h.kind, idx = i }
        end
        snacks.picker.pick({
          source = "exemplar",
          title = "examples of " .. session.word,
          items = items,
          format = function(item)
            return {
              { ("%-7s "):format(item.kind), "Comment" },
              { vim.fn.fnamemodify(item.file, ":t") .. ":" .. item.pos[1] .. "  ", "Directory" },
              { item.text },
            }
          end,
          preview = "file",
          confirm = "jump",
        })
        return
      end
      util.notify_once("snacks-missing", 'picker = "snacks" is set but snacks.nvim is not loaded. Using the built-in list.')
    end
    if config.options.picker == "select" then
      local items = {}
      for i = 1, math.min(config.options.limit, #session.results) do items[i] = session.results[i] end
      vim.ui.select(items, {
        prompt = "examples of " .. sym.word,
        format_item = function(h) return ("%s %s:%d  %s"):format(h.kind, vim.fn.fnamemodify(h.path, ":t"), h.lnum, vim.trim(h.text)) end,
      }, function(h)
        if h then vim.cmd("edit " .. vim.fn.fnameescape(h.path)); pcall(vim.api.nvim_win_set_cursor, 0, { h.lnum, (h.col or 1) - 1 }) end
      end)
      return
    end
    require("exemplar.ui.list").open(session)
  end)
end

local function step(count)
  local s = M.session
  if not s or #s.results == 0 then
    util.notify("No examples yet. Run :Exemplar on a symbol first.", vim.log.levels.WARN)
    return
  end
  local n = #s.results
  s.index = ((s.index - 1 + count) % n) + 1
  require("exemplar.ui.list").peek(s.results[s.index], s)
end

--- Next example as a preview next to the cursor. Counts work.
function M.next(count) step(count or 1) end
function M.prev(count) step(-(count or 1)) end

--- Preview for the symbol under the cursor, debounced, no list.
function M.peek()
  if peek_timer then peek_timer:stop() end
  peek_timer = vim.defer_fn(function()
    local buf = vim.api.nvim_get_current_buf()
    local sym, lang = resolve(nil, buf)
    if not sym or not lang then return end
    M.search(sym, lang, buf, function(session)
      if session and #session.results > 0 then
        M.session = session
        require("exemplar.ui.list").peek(session.results[session.index], session)
      end
    end)
  end, config.options.debounce_ms)
end

--- Detected roots for a language (defaults to the current buffer's).
function M.roots(lang, refresh)
  local buf = vim.api.nvim_get_current_buf()
  lang = lang or util.lang_of(buf)
  if not lang then return {}, { "This buffer has no filetype." } end
  return roots.get(lang, buf, refresh)
end

--- Current results to the quickfix list.
function M.quickfix()
  local s = M.session
  if not s then util.notify("No examples yet. Run :Exemplar on a symbol first.", vim.log.levels.WARN) return end
  local items = {}
  for _, h in ipairs(s.results) do
    items[#items + 1] = { filename = h.path, lnum = h.lnum, col = h.col, text = ("[%s] %s"):format(h.kind, vim.trim(h.text)) }
  end
  vim.fn.setqflist({}, " ", { title = "exemplar: " .. s.word, items = items })
  vim.cmd("copen")
end

--- Compare the names declared in this file with the library. See names.lua.
function M.names(buf)
  require("exemplar.names").run(buf)
end

function M.clear_cache()
  cache = {}
  roots.clear()
  require("exemplar.libindex").clear()
end

return M
