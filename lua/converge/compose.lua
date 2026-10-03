---Mix snapshots by recipe. Pure: no Neovim state is read or changed.
local slices = require("converge.slices")

local M = {}

---@param recipe table<string, string> every slice filled
---@param snaps table<string, table> theme name -> snapshot
---@return {background: string, groups: table<string, table>, terminal: table<string, string>}
function M.compose(recipe, snaps)
  local out = {
    background = snaps[recipe.ui].background,
    groups = {},
    terminal = snaps[recipe.terminal].terminal or {},
  }
  for _, slice in ipairs(slices.names) do
    if slice ~= "terminal" then
      for group, attrs in pairs(snaps[recipe[slice]].groups) do
        if slices.slice_of(group) == slice then
          out.groups[group] = attrs
        end
      end
    end
  end
  return out
end

return M
