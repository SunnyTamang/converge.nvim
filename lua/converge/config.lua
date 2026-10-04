---Options and recipe handling.
local log = require("converge.log")
local slices = require("converge.slices")
local overrides = require("converge.overrides")
local store = require("converge.store")

local M = {}

---@type {recipe: table}
M.options = { recipe = {} }

---Return a clean copy of `recipe`: only known slices with usable theme names, plus cleaned
---`overrides` when `keep_overrides` is true (a saved recipe holds slices only, so its
---`overrides` key is dropped without a warning).
---@param recipe any
---@param where string where the recipe came from, for warnings
---@param keep_overrides boolean|nil
---@return table
function M.validate(recipe, where, keep_overrides)
  local clean = {}
  if type(recipe) ~= "table" then
    log.warn(where .. ": recipe must be a table")
    return clean
  end
  local keys = vim.tbl_keys(recipe)
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    local value = recipe[key]
    if key == "overrides" then
      if keep_overrides then
        clean.overrides = overrides.validate(value, where)
      end
    elseif not slices.is_slice(key) then
      log.warn(string.format("%s: unknown slice '%s' ignored", where, tostring(key)))
    elseif type(value) ~= "string" or value == "" then
      log.warn(string.format("%s: theme for '%s' must be a non-empty string", where, key))
    elseif value == "converge" then
      log.warn(string.format("%s: theme for '%s' cannot be 'converge'", where, key))
    else
      clean[key] = value
    end
  end
  return clean
end

---@param opts {recipe?: table}|nil
function M.setup(opts)
  opts = opts or {}
  M.options = { recipe = M.validate(opts.recipe or {}, "setup", true) }
end

---Fill every slice. A missing slice uses the ui theme; a missing ui uses "default".
---`overrides` is carried over unchanged.
---@param recipe table
---@return table
function M.complete(recipe)
  local ui = recipe.ui or "default"
  local full = {}
  for _, name in ipairs(slices.names) do
    full[name] = recipe[name] or ui
  end
  full.overrides = recipe.overrides
  return full
end

---The active recipe, every slice filled. Slices: the saved recipe wins over setup().
---Overrides: always from setup().
---@return table
function M.resolve()
  local saved, err = store.read()
  if err then
    log.warn(err)
  end
  local base = saved and M.validate(saved, "saved recipe", false) or M.options.recipe
  local full = M.complete(base)
  full.overrides = M.options.recipe.overrides
  return full
end

---Only the slice entries of `recipe` (what the picker saves).
---@param recipe table
---@return table<string, string>
function M.slices_of(recipe)
  local out = {}
  for _, name in ipairs(slices.names) do
    out[name] = recipe[name]
  end
  return out
end

---Recipe as Lua text, ready to paste into `setup({ ... })`.
---@param recipe table
---@return string
function M.to_lua(recipe)
  local lines = { "recipe = {" }
  for _, name in ipairs(slices.names) do
    if recipe[name] then
      table.insert(lines, string.format("  %s = %q,", name, recipe[name]))
    end
  end
  if recipe.overrides then
    vim.list_extend(lines, overrides.to_lua_lines(recipe.overrides, "  "))
  end
  table.insert(lines, "},")
  return table.concat(lines, "\n")
end

return M
