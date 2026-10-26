local M = {}

M.defaults = {
  backend = "auto",        -- "auto" | "rg" | "git" | "grep"
  limit = 10,              -- results shown first; `m` in the list shows more
  context = 6,             -- preview lines around the hit when no enclosing block is found
  max_block = 40,          -- longest enclosing block shown in the preview
  diverse = true,          -- at most 2 hits per file and 4 per directory
  show_definitions = true, -- keep definitions, tagged and ranked low
  debounce_ms = 150,       -- for peek() only
  picker = "builtin",      -- "builtin" | "snacks" | "select"
  project_config = false,  -- load .exemplar.lua from the project root
  roots = {},              -- per-language overrides: { zig = { "/path", { path = "...", kind = "compiler" } } }
  languages = {},          -- per-language settings: { zig = { compiler_src = "~/src/zig" } }
  max_hits = 3000,         -- stop reading search output after this many hits
  per_file = 20,           -- hits per file the backend may return
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
