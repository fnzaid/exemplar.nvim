local util = require("exemplar.util")
local M = {}

function M.detect(ctx)
  local roots, notes = {}, {}
  local out, err = util.run({ "rustc", "--print", "sysroot" })
  if not out then
    notes[#notes + 1] = ("I ran `rustc --print sysroot` and it failed: %s. Install Rust, or set roots.rust in setup()."):format(err)
  else
    local sysroot = vim.trim(out)
    local src = sysroot .. "/lib/rustlib/src/rust/library"
    if util.isdir(src) then
      roots[#roots + 1] = { path = src, kind = "std" }
    else
      notes[#notes + 1] = ("I found Rust at %s but the standard library source is not installed. Run `rustup component add rust-src`."):format(sysroot)
    end
  end
  if ctx.opts.registry ~= false then
    local cargo = os.getenv("CARGO_HOME") or (os.getenv("HOME") or "") .. "/.cargo"
    local reg = cargo .. "/registry/src"
    if util.isdir(reg) then roots[#roots + 1] = { path = reg, kind = "package" } end
  end
  return roots, notes
end

return M
