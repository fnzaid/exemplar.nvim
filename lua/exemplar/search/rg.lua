local M = {}

function M.run(q, cb)
  local args = { "rg", "--json", "--no-messages", "--max-count", tostring(q.per_file), "--max-filesize", "2M" }
  if q.pattern.fixed then args[#args + 1] = "--fixed-strings" end
  if q.pattern.word then args[#args + 1] = "--word-regexp" end
  for _, g in ipairs(q.globs) do
    args[#args + 1] = "-g"
    args[#args + 1] = g
  end
  args[#args + 1] = "--"
  args[#args + 1] = q.pattern.text
  for _, p in ipairs(q.paths) do args[#args + 1] = p end

  local proc = vim.system(args, { text = true }, function(res)
    if res.code ~= 0 and res.code ~= 1 then
      cb({}, ("ripgrep failed: %s"):format(vim.trim(res.stderr or ("exit code " .. res.code))), false)
      return
    end
    local hits, partial = {}, false
    for line in (res.stdout or ""):gmatch("[^\n]+") do
      if #hits >= q.max_hits then partial = true break end
      if line:find('"type":"match"', 1, true) then
        local ok, obj = pcall(vim.json.decode, line)
        if ok and obj.data and obj.data.path and obj.data.path.text then
          local sm = obj.data.submatches and obj.data.submatches[1]
          hits[#hits + 1] = {
            path = obj.data.path.text,
            lnum = obj.data.line_number,
            col = (sm and sm.start or 0) + 1,
            text = (obj.data.lines.text or ""):gsub("[\r\n]+$", ""),
          }
        end
      end
    end
    cb(hits, nil, partial)
  end)
  return { kill = function() pcall(proc.kill, proc, 15) end }
end

return M
