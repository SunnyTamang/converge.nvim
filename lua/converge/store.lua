---The recipe saved by the picker.
local jsonfile = require("converge.jsonfile")

local M = {}

---@return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "converge", "recipe.json")
end

---@return table|nil recipe nil when there is no saved recipe
---@return string|nil err
function M.read()
  local value, err = jsonfile.read(M.path())
  if err or (value ~= nil and type(value) ~= "table") then
    return nil, "saved recipe is broken, ignoring " .. M.path()
  end
  return value, nil
end

---@param recipe table
function M.write(recipe)
  jsonfile.write(M.path(), recipe)
end

function M.delete()
  vim.fn.delete(M.path())
end

return M
