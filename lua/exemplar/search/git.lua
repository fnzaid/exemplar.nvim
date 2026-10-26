local M = {}

-- One `git grep` per root. Roots that are not git repositories are skipped.
function M.run(q, cb)
  local pending, hits, partial, skipped = #q.paths, {}, false, 0
  local procs = {}
  if pending == 0 then cb({}, nil, false) return { kill = function() end } end

  local function finish()
    pending = pending - 1
    if pending > 0 then return end
    cb(hits, nil, partial)
  end

  for _, root in ipairs(q.paths) do
    local args = { "git", "-C", root, "grep", "-n", "--column", "-I", "--no-color" }
    if q.pattern.fixed then args[#args + 1] = "-F" else args[#args + 1] = "-E" end
    if q.pattern.word then args[#args + 1] = "-w" end
    args[#args + 1] = "-e"
    args[#args + 1] = q.pattern.text
    args[#args + 1] = "--"
    for _, g in ipairs(q.globs) do args[#args + 1] = g end
    procs[#procs + 1] = vim.system(args, { text = true }, function(res)
      if res.code == 128 then skipped = skipped + 1 end
      if res.code == 0 then
        local per = {}
        for line in (res.stdout or ""):gmatch("[^\n]+") do
          if #hits >= q.max_hits then partial = true break end
          local path, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
          if path then
            per[path] = (per[path] or 0) + 1
            if per[path] <= q.per_file then
              hits[#hits + 1] = { path = root .. "/" .. path, lnum = tonumber(lnum), col = tonumber(col), text = text }
            end
          end
        end
      end
      finish()
    end)
  end
  return { kill = function() for _, p in ipairs(procs) do pcall(p.kill, p, 15) end end }
end

return M
