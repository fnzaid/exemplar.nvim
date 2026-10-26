local util = require("exemplar.util")
local M = {}

--- `zig env` has printed JSON, key="value" lines, and ZON in different
--- versions. One pattern reads a quoted path after a key in all three.
local function field(out, key)
  return out:match(key .. '"?%s*[=:]%s*"([^"]+)"')
end

function M.detect(ctx)
  local roots, notes = {}, {}
  local out, err = util.run({ "zig", "env" })
  if not out then
    notes[#notes + 1] = ("I ran `zig env` to find the standard library and it failed: %s. Install Zig, or set roots.zig = { \"/path/to/zig/lib/std\" } in setup()."):format(err)
  else
    local std = field(out, "std_dir")
    local lib = field(out, "lib_dir")
    local cache = field(out, "global_cache_dir")
    if std then
      roots[#roots + 1] = { path = std, kind = "std" }
    elseif lib then
      roots[#roots + 1] = { path = lib .. "/std", kind = "std" }
    else
      notes[#notes + 1] = "I ran `zig env` but found no std_dir or lib_dir in its output."
    end
    if cache then roots[#roots + 1] = { path = cache .. "/p", kind = "package" } end
  end
  if ctx.opts.compiler_src then
    roots[#roots + 1] = { path = ctx.opts.compiler_src, kind = "compiler" }
  end
  return roots, notes
end

return M
