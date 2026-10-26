local util = require("exemplar.util")
local M = {}

function M.detect(ctx)
  local roots, notes = {}, {}
  local py = ctx.opts.python
  if not py then
    local venv = os.getenv("VIRTUAL_ENV")
    if venv and util.isdir(venv) then
      py = venv .. "/bin/python"
    elseif util.isdir(ctx.project .. "/.venv") then
      py = ctx.project .. "/.venv/bin/python"
    else
      py = vim.fn.executable("python3") == 1 and "python3" or "python"
    end
  end
  local code = "import json,sys,sysconfig,site;print(json.dumps({'stdlib':sysconfig.get_paths()['stdlib'],'site':site.getsitepackages()+([site.getusersitepackages()] if hasattr(site,'getusersitepackages') else [])}))"
  local out, err = util.run({ py, "-c", code })
  if not out then
    notes[#notes + 1] = ("I ran %s to find the standard library and it failed: %s. Install Python, or set roots.python in setup()."):format(py, err)
    return roots, notes
  end
  local ok, data = pcall(vim.json.decode, out)
  if not ok then
    notes[#notes + 1] = "Python answered but I could not read the paths it printed."
    return roots, notes
  end
  if data.stdlib then roots[#roots + 1] = { path = data.stdlib, kind = "std" } end
  for _, p in ipairs(data.site or {}) do roots[#roots + 1] = { path = p, kind = "package" } end
  return roots, notes
end

return M
