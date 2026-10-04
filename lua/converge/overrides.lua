---Single-group overrides: validation and small helpers. Only `validate` has a side effect
---(warnings).
local log = require("converge.log")

local M = {}

---@param t table
---@return any[]
function M.sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function is_name(value)
  return type(value) == "string" and value ~= ""
end

local function clean_from(from, where)
  local out = {}
  if type(from) ~= "table" then
    log.warn(where .. ": overrides.from must be a table")
    return out
  end
  for _, theme in ipairs(M.sorted_keys(from)) do
    local groups = from[theme]
    if not is_name(theme) then
      log.warn(where .. ": overrides.from theme names must be non-empty strings")
    elseif theme == "converge" then
      log.warn(where .. ": overrides.from cannot use 'converge'")
    elseif type(groups) ~= "table" or not vim.islist(groups) then
      log.warn(string.format("%s: overrides.from.%s must be a list of group names", where, theme))
    else
      local list = {}
      for _, group in ipairs(groups) do
        if is_name(group) then
          table.insert(list, group)
        else
          log.warn(
            string.format("%s: overrides.from.%s has an invalid group name, ignored", where, theme)
          )
        end
      end
      if #list > 0 then
        out[theme] = list
      end
    end
  end
  return out
end

local function clean_set(set, where)
  local out = {}
  if type(set) ~= "table" then
    log.warn(where .. ": overrides.set must be a table")
    return out
  end
  for _, group in ipairs(M.sorted_keys(set)) do
    if not is_name(group) then
      log.warn(where .. ": overrides.set group names must be non-empty strings")
    elseif type(set[group]) ~= "table" then
      log.warn(string.format("%s: overrides.set.%s must be a table, ignored", where, group))
    else
      out[group] = set[group]
    end
  end
  return out
end

---Clean a recipe's `overrides` value. Bad parts warn once and are dropped.
---@param value any
---@param where string where the recipe came from, for warnings
---@return {from: table<string, string[]>, set: table<string, table>}|nil nil when nothing is left
function M.validate(value, where)
  if value == nil then
    return nil
  end
  if type(value) ~= "table" then
    log.warn(where .. ": overrides must be a table")
    return nil
  end
  local from, set = {}, {}
  for _, key in ipairs(M.sorted_keys(value)) do
    if key == "from" then
      from = clean_from(value.from, where)
    elseif key == "set" then
      set = clean_set(value.set, where)
    else
      log.warn(string.format("%s: unknown overrides key '%s' ignored", where, tostring(key)))
    end
  end
  if vim.tbl_isempty(from) and vim.tbl_isempty(set) then
    return nil
  end
  return { from = from, set = set }
end

---Theme names used by `from`, sorted.
---@param ov table|nil
---@return string[]
function M.themes(ov)
  return ov and M.sorted_keys(ov.from) or {}
end

---@param ov table|nil
---@return integer from_groups
---@return integer set_groups
function M.counts(ov)
  if not ov then
    return 0, 0
  end
  local from = 0
  for _, groups in pairs(ov.from) do
    from = from + #groups
  end
  return from, vim.tbl_count(ov.set)
end

local function lua_key(name)
  if name:match("^[%a_][%w_]*$") then
    return name
  end
  return string.format("[%q]", name)
end

---Lua source for `overrides = { ... },`, as lines prefixed with `indent`.
---@param ov {from: table<string, string[]>, set: table<string, table>}
---@param indent string
---@return string[]
function M.to_lua_lines(ov, indent)
  local inner = indent .. "  "
  local lines = { indent .. "overrides = {" }
  if not vim.tbl_isempty(ov.from) then
    table.insert(lines, inner .. "from = {")
    for _, theme in ipairs(M.sorted_keys(ov.from)) do
      local quoted = vim.tbl_map(function(group)
        return string.format("%q", group)
      end, ov.from[theme])
      table.insert(
        lines,
        string.format("%s  %s = { %s },", inner, lua_key(theme), table.concat(quoted, ", "))
      )
    end
    table.insert(lines, inner .. "},")
  end
  if not vim.tbl_isempty(ov.set) then
    table.insert(lines, inner .. "set = {")
    for _, group in ipairs(M.sorted_keys(ov.set)) do
      local value = vim.inspect(ov.set[group], { newline = " ", indent = "" })
      table.insert(lines, string.format("%s  %s = %s,", inner, lua_key(group), value))
    end
    table.insert(lines, inner .. "},")
  end
  table.insert(lines, indent .. "},")
  return lines
end

return M
