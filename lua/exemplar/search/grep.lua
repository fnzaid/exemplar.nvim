local M = {}

function M.run(q, cb)
  local args = { "grep", "-rnI", "--no-messages" }
  if q.pattern.fixed then args[#args + 1] = "-F" else args[#args + 1] = "-E" end
  if q.pattern.word then args[#args + 1] = "-w" end
  for _, g in ipairs(q.globs) do args[#args + 1] = "--include=" .. g end
  args[#args + 1] = "-e"
  args[#args + 1] = q.pattern.text
  for _, p in ipairs(q.paths) do args[#args + 1] = p end
  local proc = vim.system(args, { text = true }, function(res)
    if res.code ~= 0 and res.code ~= 1 then
      cb({}, ("grep failed: %s"):format(vim.trim(res.stderr or ("exit code " .. res.code))), false)
      return
    end
    local hits, partial, per = {}, false, {}
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      if #hits >= q.max_hits then partial = true break end
      local path, lnum, text = line:match("^(.-):(%d+):(.*)$")
      if path then
        per[path] = (per[path] or 0) + 1
        if per[path] <= q.per_file then
          local col = text:find(q.pattern.text, 1, q.pattern.fixed) or 1
          hits[#hits + 1] = { path = path, lnum = tonumber(lnum), col = col, text = text }
        end
      end
    end
    cb(hits, nil, partial)
  end)
  return { kill = function() pcall(proc.kill, proc, 15) end }
end

return M
