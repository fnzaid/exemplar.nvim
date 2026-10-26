-- Names declared in a buffer. Three ways, best first:
--   1. the language's `locals` query (shipped by nvim-treesitter)
--   2. a walk over the parse tree for definition-shaped nodes
--   3. line patterns, when there is no parser at all
local M = {}

-- Node types that declare something, across the grammars we care about.
local decl_types = {
  function_declaration = "function", function_definition = "function", local_function = "function",
  function_item = "function", method_declaration = "function", method_definition = "function",
  FnProto = "function", test_declaration = "function",
  struct_item = "type", enum_item = "type", trait_item = "type", type_item = "type", union_item = "type",
  class_definition = "type", class_declaration = "type", interface_declaration = "type",
  type_alias_declaration = "type", enum_declaration = "type", type_spec = "type",
  struct_specifier = "type", enum_specifier = "type", type_definition = "type", ContainerDecl = "type",
  const_item = "var", static_item = "var", let_declaration = "var", var_spec = "var", const_spec = "var",
  short_var_declaration = "var", variable_declaration = "var", local_variable_declaration = "var",
  variable_declarator = "var", VarDecl = "var",
}

local skip_types = { lexical_declaration = true, declaration = true }

local patterns = {
  lua = { "local%s+function%s+([%w_]+)", "function%s+[%w_.:]-([%w_]+)%s*%(", "local%s+([%w_]+)%s*=" },
  zig = { "fn%s+([%w_]+)", "const%s+([%w_]+)%s*=", "var%s+([%w_]+)%s*[:=]" },
  rust = { "fn%s+([%w_]+)", "struct%s+([%w_]+)", "enum%s+([%w_]+)", "trait%s+([%w_]+)", "let%s+mut%s+([%w_]+)", "let%s+([%w_]+)" },
  go = { "func%s+([%w_]+)", "func%s+%b()%s*([%w_]+)", "type%s+([%w_]+)", "^%s*([%w_]+)%s*:=", "var%s+([%w_]+)" },
  python = { "def%s+([%w_]+)", "class%s+([%w_]+)", "^%s*([%w_]+)%s*=" },
  javascript = { "function%s+([%w_$]+)", "class%s+([%w_$]+)", "const%s+([%w_$]+)", "let%s+([%w_$]+)", "var%s+([%w_$]+)" },
  c = { "^[%w_%*%s]-%s%*?([%w_]+)%s*%([^;]*$", "struct%s+([%w_]+)", "typedef%s+.-([%w_]+)%s*;" },
}

local function is_ident(node)
  local t = node:type()
  return t == "identifier" or t:find("identifier") ~= nil or t == "IDENTIFIER" or t == "name"
end

--- The identifier that names a declaration node.
local function name_node(node)
  local f = node:field("name")[1]
  if f then
    if is_ident(f) then return f end
    -- dotted names like M.greet: the last identifier
    local last
    for child in f:iter_children() do if is_ident(child) then last = child end end
    if last then return last end
  end
  local srow = node:range()
  local function first_ident(n, depth)
    if depth > 4 then return nil end
    for child in n:iter_children() do
      local crow = child:range()
      if crow > srow then return nil end
      if is_ident(child) then return child end
      local found = first_ident(child, depth + 1)
      if found then return found end
    end
  end
  return first_ident(node, 0)
end

local function via_locals(buf, lang, root)
  local ok, query = pcall(vim.treesitter.query.get, lang, "locals")
  if not ok or not query then return nil end
  local out, seen = {}, {}
  for id, node in query:iter_captures(root, buf) do
    local cap = query.captures[id]
    local kind = cap:match("^local%.definition%.?(%w*)") or cap:match("^definition%.?(%w*)")
    if kind and kind ~= "parameter" and kind ~= "import" and kind ~= "namespace" and kind ~= "field" then
      local text = vim.treesitter.get_node_text(node, buf)
      local row = node:range()
      if text:match("^[%a_$][%w_$]*$") and not seen[text] then
        seen[text] = true
        out[#out + 1] = { name = text, lnum = row + 1, kind = kind ~= "" and kind or "var" }
      end
    end
  end
  return #out > 0 and out or nil
end

local function via_walk(buf, root)
  local out, seen = {}, {}
  local function walk(node)
    local t = node:type()
    local kind = decl_types[t]
    if kind and not skip_types[t] then
      local n = name_node(node)
      if n then
        local text = vim.treesitter.get_node_text(n, buf)
        local row = n:range()
        if text:match("^[%a_$][%w_$]*$") and not seen[text] then
          seen[text] = true
          out[#out + 1] = { name = text, lnum = row + 1, kind = kind }
        end
      end
    end
    for child in node:iter_children() do walk(child) end
  end
  walk(root)
  return out
end

local function via_patterns(buf, lang)
  local pats = patterns[lang]
  if not pats then return {} end
  local out, seen = {}, {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for _, p in ipairs(pats) do
      local name = line:match(p)
      if name and not seen[name] then
        seen[name] = true
        out[#out + 1] = { name = name, lnum = lnum, kind = "var" }
        break
      end
    end
  end
  return out
end

--- Declarations in `buf`: { name, lnum, kind }[] and the method used.
---@return table[], "locals"|"tree"|"patterns"
function M.get(buf, lang)
  buf = buf or vim.api.nvim_get_current_buf()
  local tslang = vim.treesitter.language.get_lang(vim.bo[buf].filetype) or lang
  local okp, parser = pcall(vim.treesitter.get_parser, buf, tslang, { error = false })
  if okp and parser then
    local okt, trees = pcall(parser.parse, parser, true)
    if okt and trees and trees[1] then
      local root = trees[1]:root()
      local found = via_locals(buf, tslang, root)
      if found then return found, "locals" end
      found = via_walk(buf, root)
      if #found > 0 then return found, "tree" end
    end
  end
  return via_patterns(buf, lang), "patterns"
end

return M
