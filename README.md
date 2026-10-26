# exemplar.nvim

I kept getting stuck the same way. I know the function exists. I know
roughly what it does. I do not know how to call it. The docs show me the
signature. What I need is to see someone use it.

So I would open the standard library and grep. Every time. Then scroll
through a hundred hits, half of them tests, to find three good ones.

This plugin does that grep for me and keeps the good ones.

Put the cursor on a name. Run `:Exemplar`. You get the ten best real uses
of it from the standard library and the packages already on your disk.
Each one is shown inside the function it lives in, with the line marked.
`n` for the next one. `2n` to skip one. `<CR>` to open it. `q` to go back
to work.

No network. No account. No index to build. The examples come from the
exact version of the library you compile against.

Works for Zig, Rust, Go, JavaScript and TypeScript, Python, C and C++, and
Lua. Early. Tell me what breaks.

## Install

LazyVim or lazy.nvim, in `lua/plugins/exemplar.lua`:

```lua
return {
  "fnzaid/exemplar.nvim",
  cmd = "Exemplar",
  keys = {
    { "<leader>se", function() require("exemplar").show() end, desc = "Examples of symbol" },
    { "]x", function() require("exemplar").next(vim.v.count1) end, desc = "Next example" },
    { "[x", function() require("exemplar").prev(vim.v.count1) end, desc = "Previous example" },
  },
  opts = {},
}
```

Neovim 0.12 without a plugin manager, in `init.lua`:

```lua
vim.pack.add({ "https://github.com/fnzaid/exemplar.nvim" })
require("exemplar").setup({})
vim.keymap.set("n", "<leader>se", function() require("exemplar").show() end)
vim.keymap.set("n", "]x", function() require("exemplar").next(vim.v.count1) end)
vim.keymap.set("n", "[x", function() require("exemplar").prev(vim.v.count1) end)
```

By hand:

```sh
git clone https://github.com/fnzaid/exemplar.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/exemplar.nvim
```

Needs Neovim 0.10 or newer. ripgrep makes it fast. Without ripgrep it
uses `git grep`, and without that, `grep`.

## Use

```vim
:Exemplar               " examples of the name under the cursor
:Exemplar std.mem.tokenize
:Exemplar next 2        " next example in a small window, no list
:Exemplar roots         " where it is searching, and why not elsewhere
:Exemplar qf            " results to the quickfix list
:Exemplar names         " compare your names with the library's, dim text, any key clears
:checkhealth exemplar
:help exemplar
```

Select some text in visual mode and run `:Exemplar` to search that text.

In the list: `n` `N` move, `<CR>` open, `s` `v` open in a split, `y` yank
the line, `Y` yank the block, `m` ten more, `d` hide definitions, `<Tab>`
jump into the preview to scroll it, `q` close, `g?` help.

The keys above do not collide with LazyVim's defaults. `]e` and `[e` are
taken there (next and previous error), which is why the examples use `]x`
and `[x`.

The preview shows the whole function the example sits in. If the function
is long, its first line stays pinned at the top.

## Naming

I also get stuck on names. Is it `readAll` or `readToEnd`? Does this
library say `len` or `length` or `size`?

```vim
:Exemplar names
```

looks at every function, variable and type you declared in the current
file, searches the library for names built on the same word, and shows
the three most common ones in dim text at the end of the line, with how
often each appears. If the library uses a different casing style from
yours, it says so. If your exact name already exists in the library, it
says that instead.

Press any key and the text goes away. `:Exemplar names clear` also works.

It is a heuristic. It reads declarations with simple patterns, not a
parser, so it can miss some and it never changes your code.

## Where it looks

It asks your toolchain. `zig env`, `rustc --print sysroot`, `go env`, the
nearest `node_modules`, Python's own paths, the C compiler's include list,
Neovim's runtime. Your project is searched too, ranked last.

If a toolchain is missing it tells you which command failed and which line
in `setup()` fixes it. To add a place yourself, like the compiler source
you cloned last year:

```lua
require("exemplar").setup({
  roots = {
    zig = { { path = "~/src/zig", kind = "compiler" } },
  },
})
```

## How it ranks

Standard library first, then packages, then your project. Lines that use
the full name (`std.mem.tokenize`, not just `tokenize`) go up. Calls go up.
Definitions stay in the list with a `def` tag but go down. Test files go
down a little. The same line found in many files counts once. Hits inside
strings and comments are dropped. No more than two hits from the same file
in the top ten.

A short name like `init` can match thousands of lines. When that happens
and you searched a dotted name, exemplar searches again for the last two
parts, `ArrayList.init`, and shows those instead.

The weights are one table in `lua/exemplar/rank.lua`. If you find a better
set, open an issue.

## Options

```lua
require("exemplar").setup({
  backend = "auto",        -- "auto" | "rg" | "git" | "grep"
  limit = 10,              -- how many to show first
  context = 6,             -- lines around the hit when no function is found
  max_block = 40,          -- longest function shown whole
  diverse = true,          -- spread hits across files
  show_definitions = true, -- keep definitions, tagged, ranked low
  picker = "builtin",      -- "snacks" uses the snacks.nvim picker, "select" uses vim.ui.select
  roots = {},              -- add or replace search places per language
  languages = {},          -- e.g. { zig = { compiler_src = "~/src/zig" } }
})
```

`:help exemplar-options` has the rest.

## Tests

```sh
nvim --headless -u tests/init.lua +q
```

CI runs them on Linux, macOS and Windows, on stable and nightly Neovim.

## Not planned

Web search. Anything that generates code. A background indexer. If
ripgrep over your standard library is too slow for you, tell me the
numbers.

## Licence

MIT.
