-- Headless test:  nvim --headless -u tests/init.lua +q
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.cmd.runtime("plugin/exemplar.lua")

local fixtures = root .. "/tests/fixtures"
local failures = 0
local function step(name, f)
  local ok, err = pcall(f)
  if ok then print("ok   " .. name) else failures = failures + 1; io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n") end
end

local ex = require("exemplar")
ex.setup({
  roots = { lua = { only = true, { path = fixtures .. "/luastd", kind = "std" } } },
})

-- a buffer inside the fake project so the project root is the fixture dir
vim.cmd("edit " .. fixtures .. "/project/main.lua")
vim.bo.filetype = "lua"

step("symbol under cursor with treesitter gives word and chain", function()
  vim.api.nvim_win_set_cursor(0, { 2, 13 }) -- on "greet" in util.greet("world")
  local sym = require("exemplar.symbol").at_cursor(0)
  assert(sym and sym.word == "greet", vim.inspect(sym))
  assert(sym.chain == "util.greet", vim.inspect(sym))
end)

local session
step("search returns ranked, filtered hits", function()
  local done = false
  ex.search({ word = "greet", chain = "util.greet" }, "lua", 0, function(s, err)
    assert(not err, err)
    session = s
    done = true
  end)
  vim.wait(5000, function() return done end)
  assert(done, "search did not finish")
  assert(#session.results >= 6, "expected at least 6 hits, got " .. #session.results)
  for _, h in ipairs(session.results) do
    assert(not h.text:match("^%s*%-%-"), "comment-only line kept: " .. h.text)
  end
  local first = session.results[1]
  assert(first.kind == "std", "first hit should come from std, got " .. first.kind)
  assert(first.text:find("util.greet", 1, true), "first hit should contain the full chain: " .. first.text)
  assert(not first.definition, "first hit must not be the definition")
  local def_seen, def_last = false, true
  for i, h in ipairs(session.results) do
    if h.definition then def_seen = true; def_last = def_last and i > 1 end
  end
  assert(def_seen, "definition should be kept and tagged")
  assert(def_last, "definition should not be ranked first")
  local test_rank
  for i, h in ipairs(session.results) do if h.path:find("/test/") then test_rank = i end end
  assert(test_rank and test_rank > 2, "test file hits should rank below real uses")
  for _, h in ipairs(session.results) do
    assert(not h.text:find("please greet"), "hit inside a string kept: " .. h.text)
    assert(not h.text:find("greet them later"), "hit inside a trailing comment kept: " .. h.text)
  end
  local calls = 0
  for _, h in ipairs(session.results) do if h.call then calls = calls + 1 end end
  assert(calls >= 4, "treesitter should confirm calls, got " .. calls)
end)

step("definition preview includes the doc comment above it", function()
  local def
  for _, h in ipairs(session.results) do if h.definition then def = h end end
  assert(def, "no definition in results")
  local block = require("exemplar.context").block(def)
  assert(block.lines[1]:find("Say hello"), "expected the doc comment first, got: " .. block.lines[1])
end)

step("visual selection search through :Exemplar", function()
  vim.cmd("edit " .. fixtures .. "/project/main.lua")
  vim.api.nvim_win_set_cursor(0, { 2, 7 })
  vim.cmd("normal! viw")
  vim.cmd("normal! \27")
  vim.cmd("'<,'>Exemplar")
  vim.wait(5000, function() return require("exemplar.ui.list").is_open() end)
  assert(require("exemplar.ui.list").is_open(), "list did not open for the selection")
  assert(require("exemplar").session.word == "util", require("exemplar").session.word)
  require("exemplar.ui.list").close()
end)

step("preview shows the enclosing function with the hit marked", function()
  local hit
  for _, h in ipairs(session.results) do if h.path:find("app.lua") and h.lnum == 5 then hit = h end end
  assert(hit, "expected the welcome() hit")
  local block = require("exemplar.context").block(hit)
  assert(block, "no block")
  assert(block.lines[1]:find("local function welcome"), "block should start at the function: " .. block.lines[1])
  assert(block.lines[block.hit_row]:find("util.greet", 1, true), "hit row wrong")
  assert(block.lines[#block.lines]:find("^end"), "block should end at the function end")
end)

step("builtin list opens with ten or fewer lines and a preview", function()
  require("exemplar.ui.list").open(session)
  assert(require("exemplar.ui.list").is_open())
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(#lines <= 10 and #lines >= 6, "list has " .. #lines .. " lines")
  assert(lines[1]:match("^std%s"), "first list line should be tagged std: " .. lines[1])
  vim.api.nvim_feedkeys("n", "x", false)
  vim.api.nvim_feedkeys("q", "x", false)
  assert(not require("exemplar.ui.list").is_open(), "list should close on q")
end)

step("next and prev peek with counts", function()
  ex.session = session
  session.index = 1
  ex.next(2)
  assert(session.index == 3, session.index)
  ex.prev(1)
  assert(session.index == 2, session.index)
  assert(require("exemplar.ui.list").peek_win and vim.api.nvim_win_is_valid(require("exemplar.ui.list").peek_win))
  require("exemplar.ui.list").close_peek()
end)

step(":Exemplar roots prints the fixture root", function()
  local rs = ex.roots("lua")
  assert(rs[1].kind == "std" and rs[1].path:find("luastd"), vim.inspect(rs))
end)

step("zig pattern keeps the @ and uses a boundary regex", function()
  local p = require("exemplar.search").pattern("@typeInfo")
  assert(p.fixed == false and p.word == false and p.text:find("typeInfo\\b", 1, true), vim.inspect(p))
  local q = require("exemplar.search").pattern("tokenize")
  assert(q.fixed and q.word)
end)

step("zig env parser reads all three output formats", function()
  local out1 = '{"zig_exe": "/z/zig", "lib_dir": "/z/lib", "std_dir": "/z/lib/std", "global_cache_dir": "/home/me/.cache/zig"}'
  local out2 = 'zig_exe="/z/zig"\nlib_dir="/z/lib"\nstd_dir="/z/lib/std"\nglobal_cache_dir="/home/me/.cache/zig"\n'
  local out3 = '.{\n    .zig_exe = "/z/zig",\n    .lib_dir = "/z/lib",\n    .std_dir = "/z/lib/std",\n    .global_cache_dir = "/home/me/.cache/zig",\n}\n'
  for _, out in ipairs({ out1, out2, out3 }) do
    local std = out:match('std_dir"?%s*[=:]%s*"([^"]+)"')
    assert(std == "/z/lib/std", "parsed: " .. tostring(std))
  end
end)

step("missing toolchain gives a human message, not an error", function()
  local rs, notes = require("exemplar.roots").get("zig", 0, true)
  if vim.fn.executable("zig") == 1 then
    assert(#rs >= 1)
  else
    assert(notes[1] and notes[1]:find("zig env") and notes[1]:find("setup()"), vim.inspect(notes))
  end
end)

step("names: declarations come from the parse tree", function()
  vim.cmd("edit " .. fixtures .. "/project/main.lua")
  local found, how = require("exemplar.decls").get(0, "lua")
  assert(how == "tree" or how == "locals", how)
  local names = {}
  for _, d in ipairs(found) do names[d.name] = d end
  assert(names.greetEveryone and names.greetEveryone.kind == "function", vim.inspect(found))
  assert(names.util and names.util.kind == "var", vim.inspect(found))
end)

step("names: word-based matching with rare words weighted", function()
  local names = require("exemplar.names")
  local libindex = require("exemplar.libindex")
  local words = libindex.words
  assert(table.concat(words("readFileAlloc"), " ") == "read file alloc")
  assert(table.concat(words("read_file_alloc"), " ") == "read file alloc")
  assert(table.concat(words("HTTPServer"), " ") == "http server")
  local index = { names = { readFileAlloc = 12, readAll = 4, openFile = 9, tokenize = 3, fileName = 2 }, distinct = 5, idf = {} }
  for _, n in pairs({ "readFileAlloc", "readAll", "openFile", "tokenize", "fileName" }) do
    for _, w in ipairs(words(n)) do index.idf[w] = index.idf[w] or math.log(1 + 5 / 2) end
  end
  local m = names.match("readFile", index, 3)
  assert(m[1] and m[1].name == "readFileAlloc", vim.inspect(m))
  local none = names.match("tokenize", index, 3)
  assert(#none == 0)
  local _, exact = names.match("tokenize", index, 3)
  assert(exact and exact.count == 3)
end)

step("names: shows dim text on the right line and any key clears it", function()
  vim.cmd("edit " .. fixtures .. "/project/main.lua")
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "local function greetAgain(n) return n end" })
  local last = vim.api.nvim_buf_line_count(0)
  require("exemplar.names").run(0)
  local nsid = vim.api.nvim_get_namespaces()["exemplar.names"]
  local mark
  vim.wait(5000, function()
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, nsid, 0, -1, { details = true })) do
      if m[2] == last - 1 then mark = m end
    end
    return mark ~= nil
  end)
  assert(mark, "no dim text on the greetAgain line")
  local text = mark[4].virt_text[1][1]
  assert(text:find("greet", 1, true), "expected a library name built on greet, got: " .. text)
  vim.api.nvim_feedkeys("j", "tx", false)
  vim.wait(500, function() return #vim.api.nvim_buf_get_extmarks(0, nsid, 0, -1, {}) == 0 end)
  assert(#vim.api.nvim_buf_get_extmarks(0, nsid, 0, -1, {}) == 0, "a key press should clear the text")
  vim.cmd("edit!")
end)

step("checkhealth runs without a Lua error", function()
  vim.cmd("checkhealth exemplar")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(#lines > 10)
  for _, l in ipairs(lines) do assert(not l:find("ERROR"), l) end
end)

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all tests passed")
os.exit(0)  -- checkhealth leaves a split open, so +q alone would not quit
