---Read and write JSON files. JSON, not Lua, so reading never runs code.
local M = {}

---@param path string
---@return any|nil value
---@return string|nil err nil when the file is fine or missing
function M.read(path)
  if not vim.uv.fs_stat(path) then
    return nil, nil
  end
  local ok, value = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if not ok then
    return nil, "broken JSON in " .. path
  end
  return value, nil
end

---@param path string
---@param value any
function M.write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

return M
