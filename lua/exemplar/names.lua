-- :Exemplar names. Compare the names declared in this file with the names
-- the library declares. Matches are scored on shared words, rare words
-- counting more, and shown as dim text at the end of the line. Any key
-- clears them.
local util = require("exemplar.util")
local roots = require("exemplar.roots")
local decls = require("exemplar.decls")
local libindex = require("exemplar.libindex")

local M = {}

local ns = vim.api.nvim_create_namespace("exemplar.names")
vim.api.nvim_set_hl(0, "ExemplarNames", { default = true, link = "NonText" })

local stop = {
  get = true, set = true, is = true, has = true, new = true, init = true, data = true, value = true,
  tmp = true, temp = true, result = true, res = true, ret = true, the = true, this = true, self = true,
  main = true, test = true, foo = true, bar = true, item = true, items = true, list = true, name = true,
  fn = true, func = true, var = true, val = true, obj = true, arg = true, args = true, a = true, b = true,
}

function M.casing(name)
  if name:find("_") and not name:find("%u") then return "snake_case" end
  if name:match("^%u") and name:find("%l") then return "PascalCase" end
  if name:match("^%l") and name:find("%u") then return "camelCase" end
  if not name:find("%u") then return "lowercase" end
  return "UPPER_CASE"
end

--- Score library names against one declared name. Returns the best few.
function M.match(name, index, limit)
  local mine = {}
  local mine_weight = 0
  for _, w in ipairs(libindex.words(name)) do
    if not stop[w] and #w >= 3 then
      mine[w] = index.idf[w] or math.log(1 + index.distinct)
      mine_weight = mine_weight + mine[w]
    end
  end
  if mine_weight == 0 then return {}, nil end

  local exact = index.names[name] and { name = name, count = index.names[name] } or nil
  local lower = name:lower()
  local scored = {}
  for cand, count in pairs(index.names) do
    if cand ~= name then
      local shared, extra = 0, 0
      local cand_words = libindex.words(cand)
      for _, w in ipairs(cand_words) do
        if mine[w] then shared = shared + mine[w] elseif not stop[w] then extra = extra + 1 end
      end
      if shared > 0 then
        -- coverage of my words, a small penalty for unrelated extra words,
        -- a nudge for the same casing and for same spelling in other case
        local score = shared / mine_weight - 0.08 * extra
        if M.casing(cand) == M.casing(name) then score = score + 0.05 end
        if cand:lower() == lower then score = score + 0.5 end
        if score > 0.15 then
          scored[#scored + 1] = { name = cand, count = count, score = score }
        end
      end
    end
  end
  table.sort(scored, function(a, b)
    if math.abs(a.score - b.score) > 0.01 then return a.score > b.score end
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(limit or 3, #scored) do out[i] = scored[i] end
  return out, exact
end

local active = {}

function M.clear(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  if active[buf] then
    pcall(vim.api.nvim_del_augroup_by_id, active[buf].group)
    active[buf] = nil
  end
  vim.on_key(nil, ns)
end

local function style_hint(name, matches)
  local mine = M.casing(name)
  local styles = {}
  for _, m in ipairs(matches) do
    local s = M.casing(m.name)
    styles[s] = (styles[s] or 0) + m.count
  end
  local top, topn = nil, 0
  for s, n in pairs(styles) do if n > topn then top, topn = s, n end end
  if top and top ~= mine and mine ~= "lowercase" and top ~= "lowercase" then
    return (" · library uses %s"):format(top)
  end
  return ""
end

local function render(buf, d, matches, exact)
  local text
  if exact then
    text = ("  ~ library has %s too (%d)"):format(exact.name, exact.count)
  elseif #matches > 0 then
    local parts = {}
    for _, m in ipairs(matches) do parts[#parts + 1] = ("%s (%d)"):format(m.name, m.count) end
    text = "  ~ library: " .. table.concat(parts, ", ") .. style_hint(d.name, matches)
  else
    return false
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, d.lnum - 1, 0, {
    virt_text = { { text, "ExemplarNames" } }, virt_text_pos = "eol", hl_mode = "combine",
  })
  return true
end

--- Run on a buffer.
function M.run(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  M.clear(buf)
  local lang = util.lang_of(buf)
  if not lang then
    util.notify("This buffer has no filetype, so I do not know which library to compare with.", vim.log.levels.WARN)
    return
  end
  local rs = roots.get(lang, buf)
  local paths = {}
  for _, r in ipairs(rs) do if r.kind ~= "project" then paths[#paths + 1] = r.path end end
  if #paths == 0 then
    util.notify(("No library roots for %s, so there is nothing to compare your names with. `:Exemplar roots` shows why."):format(lang), vim.log.levels.WARN)
    return
  end
  local found, how = decls.get(buf, lang)
  if #found == 0 then
    util.notify("No declarations found in this file.", vim.log.levels.INFO)
    return
  end

  active[buf] = { group = vim.api.nvim_create_augroup("exemplar.names." .. buf, { clear = true }) }
  vim.api.nvim_create_autocmd({ "BufLeave", "InsertEnter", "TextChanged" }, {
    group = active[buf].group, buffer = buf, once = true, callback = function() M.clear(buf) end,
  })
  vim.schedule(function()
    if active[buf] then
      vim.on_key(function() vim.schedule(function() M.clear(buf) end) end, ns)
    end
  end)

  libindex.get(lang, paths, function(index, err)
    vim.schedule(function()
      if not active[buf] then return end
      if not index then util.notify(err, vim.log.levels.WARN) return end
      local shown = 0
      for _, d in ipairs(found) do
        local matches, exact = M.match(d.name, index, 3)
        if render(buf, d, matches, exact) then shown = shown + 1 end
      end
      if shown == 0 then
        util.notify(("Nothing in the library resembles the %d names here (read with %s). That can be good."):format(#found, how), vim.log.levels.INFO)
      end
    end)
  end)
end

return M
