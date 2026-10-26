-- Preview window on the left, list on the right.
local preview = require("exemplar.ui.preview")
local config = require("exemplar.config")

local M = {}

local state = nil

local function short(path, roots)
  for _, r in ipairs(roots) do
    if path:sub(1, #r.path) == r.path then
      return path:sub(#r.path + 2)
    end
  end
  return vim.fn.fnamemodify(path, ":~:.")
end

local function format(hit, roots)
  local tag = hit.definition and "  def" or ""
  return ("%-7s %s:%d  %s%s"):format(hit.kind, short(hit.path, roots), hit.lnum, vim.trim(hit.text), tag)
end

local function close()
  if not state then return end
  for _, w in ipairs({ state.list_win, state.prev_win }) do
    if w and vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
  end
  state = nil
end

local function open_hit(hit, how)
  local origin = state and state.origin_win
  close()
  if origin and vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
  if how == "split" then vim.cmd("split") elseif how == "vsplit" then vim.cmd("vsplit") end
  vim.cmd("edit " .. vim.fn.fnameescape(hit.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { hit.lnum, math.max(0, (hit.col or 1) - 1) })
  vim.cmd("normal! zz")
end

local function update_preview()
  if not state then return end
  local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local hit = state.shown[row]
  if not hit then return end
  state.session.index = row
  local hrow, head = preview.render(state.prev_buf, hit)
  pcall(vim.api.nvim_win_set_cursor, state.prev_win, { hrow, 0 })
  vim.api.nvim_win_call(state.prev_win, function() vim.cmd("normal! zz") end)
  local name = vim.fn.fnamemodify(hit.path, ":t")
  local title = head and (" %s  %s "):format(name, head:sub(1, 60)) or (" %s:%d "):format(name, hit.lnum)
  vim.api.nvim_win_set_config(state.prev_win, { title = title, title_pos = "left" })
  vim.api.nvim_win_set_config(state.list_win, {
    title = (" exemplar: %s  %d/%d "):format(state.session.word, row, #state.session.results),
    title_pos = "left",
  })
end

local function fill_list()
  local s = state.session
  state.shown = {}
  local lines = {}
  for i = 1, math.min(state.limit, #s.results) do
    state.shown[i] = s.results[i]
    lines[i] = format(s.results[i], s.roots)
  end
  if #s.results == 0 then lines[1] = "no examples" end
  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false
  local ns = vim.api.nvim_create_namespace("exemplar.list")
  vim.api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
  for i, hit in ipairs(state.shown) do
    vim.api.nvim_buf_set_extmark(state.list_buf, ns, i - 1, 0, { end_col = 7, hl_group = "ExemplarKind" })
    local pstart, pend = lines[i]:find(short(hit.path, s.roots) .. ":" .. hit.lnum, 1, true)
    if pstart then
      vim.api.nvim_buf_set_extmark(state.list_buf, ns, i - 1, pstart - 1, { end_col = pend, hl_group = "ExemplarPath" })
    end
    if hit.definition then
      vim.api.nvim_buf_set_extmark(state.list_buf, ns, i - 1, #lines[i] - 3, { end_col = #lines[i], hl_group = "ExemplarDef" })
    end
  end
end

local function move(count)
  if not state then return end
  local n = #state.shown
  if n == 0 then return end
  local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
  row = ((row - 1 + count) % n) + 1
  vim.api.nvim_win_set_cursor(state.list_win, { row, 0 })
  update_preview()
end

local help = {
  "n / N      next / previous example (counts work: 2n)",
  "<CR>       open in the window you came from",
  "s / v      open in a split / vertical split",
  "y          yank the example line",
  "Y          yank the whole preview block",
  "m          show ten more",
  "d          show or hide definitions",
  "<Tab>      move between the list and the preview",
  "q / <Esc>  close",
}

--- Open the list for a session { word, results, roots, index }.
function M.open(session)
  close()
  local total_w = vim.o.columns
  local total_h = vim.o.lines - vim.o.cmdheight - 2
  local h = math.max(10, math.floor(total_h * 0.7))
  local w = math.max(60, math.floor(total_w * 0.9))
  local col0 = math.floor((total_w - w) / 2)
  local row0 = math.floor((total_h - h) / 2)
  local prev_w = math.floor(w * 0.58)
  local list_w = w - prev_w - 2

  state = {
    session = session,
    origin_win = vim.api.nvim_get_current_win(),
    limit = config.options.limit,
    prev_buf = preview.scratch(),
    list_buf = preview.scratch(),
  }
  state.prev_win = vim.api.nvim_open_win(state.prev_buf, false, {
    relative = "editor", row = row0, col = col0, width = prev_w, height = h,
    style = "minimal", border = "rounded", title = " example ", title_pos = "left",
  })
  state.list_win = vim.api.nvim_open_win(state.list_buf, true, {
    relative = "editor", row = row0, col = col0 + prev_w + 2, width = list_w, height = h,
    style = "minimal", border = "rounded", title = " exemplar ", title_pos = "left",
  })
  vim.wo[state.prev_win].number = true
  vim.wo[state.prev_win].cursorline = false
  vim.wo[state.prev_win].wrap = false
  vim.wo[state.list_win].cursorline = true
  vim.wo[state.list_win].wrap = false
  vim.bo[state.list_buf].filetype = "exemplar"

  fill_list()

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = state.list_buf, nowait = true, desc = desc })
  end
  map("n", function() move(vim.v.count1) end, "next example")
  map("N", function() move(-vim.v.count1) end, "previous example")
  map("<CR>", function() local hit = state.shown[vim.api.nvim_win_get_cursor(0)[1]]; if hit then open_hit(hit) end end, "open")
  map("s", function() local hit = state.shown[vim.api.nvim_win_get_cursor(0)[1]]; if hit then open_hit(hit, "split") end end, "open in split")
  map("v", function() local hit = state.shown[vim.api.nvim_win_get_cursor(0)[1]]; if hit then open_hit(hit, "vsplit") end end, "open in vsplit")
  map("y", function()
    local hit = state.shown[vim.api.nvim_win_get_cursor(0)[1]]
    if hit then vim.fn.setreg('"', vim.trim(hit.text)); vim.notify("yanked example line", vim.log.levels.INFO, { title = "exemplar" }) end
  end, "yank line")
  map("Y", function()
    local lines = vim.api.nvim_buf_get_lines(state.prev_buf, 0, -1, false)
    vim.fn.setreg('"', table.concat(lines, "\n"))
    vim.notify("yanked preview block", vim.log.levels.INFO, { title = "exemplar" })
  end, "yank block")
  map("m", function() state.limit = state.limit + config.options.limit; fill_list(); update_preview() end, "show more")
  map("d", function()
    session.hide_definitions = not session.hide_definitions
    local keep = {}
    for _, hit in ipairs(session.all) do
      if not (session.hide_definitions and hit.definition) then keep[#keep + 1] = hit end
    end
    session.results = keep
    fill_list(); update_preview()
  end, "show or hide definitions")
  map("<Tab>", function() vim.api.nvim_set_current_win(state.prev_win) end, "scroll the preview")
  vim.keymap.set("n", "<Tab>", function()
    if state and vim.api.nvim_win_is_valid(state.list_win) then vim.api.nvim_set_current_win(state.list_win) end
  end, { buffer = state.prev_buf, nowait = true, desc = "back to the list" })
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, close, { buffer = state.prev_buf, nowait = true, desc = "close" })
  end
  map("q", close, "close")
  map("<Esc>", close, "close")
  map("g?", function() vim.notify(table.concat(help, "\n"), vim.log.levels.INFO, { title = "exemplar keys" }) end, "help")

  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.list_buf, callback = update_preview })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.list_win), once = true,
    callback = function() vim.schedule(close) end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if not state then return true end
      local w = vim.api.nvim_get_current_win()
      if w ~= state.list_win and w ~= state.prev_win then close() return true end
    end,
  })

  if session.index and session.index <= #state.shown then
    vim.api.nvim_win_set_cursor(state.list_win, { session.index, 0 })
  end
  update_preview()
end

function M.is_open()
  return state ~= nil
end

function M.close()
  close()
end

--- Preview only, next to the cursor. Closes when the cursor moves.
function M.peek(hit, session)
  M.close_peek()
  local buf = preview.scratch()
  local row = preview.render(buf, hit)
  local lines = vim.api.nvim_buf_line_count(buf)
  local width = math.min(math.floor(vim.o.columns * 0.6), 100)
  local height = math.min(lines, math.floor(vim.o.lines * 0.4))
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor", row = 1, col = 0, width = width, height = height,
    style = "minimal", border = "rounded",
    title = (" %s  %d/%d  %s "):format(session.word, session.index, #session.results, hit.kind), title_pos = "left",
  })
  vim.wo[win].number = true
  pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
  vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
  M.peek_win = win
  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
    once = true, callback = function() M.close_peek() end,
  })
end

function M.close_peek()
  if M.peek_win and vim.api.nvim_win_is_valid(M.peek_win) then
    pcall(vim.api.nvim_win_close, M.peek_win, true)
  end
  M.peek_win = nil
end

return M
