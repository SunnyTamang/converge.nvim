---Warnings shown once per message per session.
local M = {}

local seen = {}

---@param msg string
function M.warn(msg)
  if seen[msg] then
    return
  end
  seen[msg] = true
  vim.notify("converge: " .. msg, vim.log.levels.WARN)
end

---Forget shown messages. Tests only.
function M._reset()
  seen = {}
end

return M
