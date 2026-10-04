---Mix snapshots by recipe. Pure: no Neovim state is read or changed.
local overrides = require("converge.overrides")
local slices = require("converge.slices")

local M = {}

-- Link chains longer than this are treated as broken (also stops cycles).
local MAX_LINK_STEPS = 20

---The closest group on `group`'s link chain that is in `named`, or nil.
---@param group string
---@param links table<string, string>
---@param named table<string, string>
---@return string|nil
local function closest_override(group, links, named)
  local current = group
  for _ = 1, MAX_LINK_STEPS do
    current = links[current]
    if current == nil then
      return nil
    end
    if named[current] then
      return current
    end
  end
  return nil
end

---Slices first, then `overrides.from`. Groups that link to an overridden group in their
---theme follow it. `overrides.set` and its followers are returned for the caller to apply
---last, so one bad value cannot stop the rest.
---@param recipe table every slice filled, optional validated `overrides`
---@param snaps table<string, table|false> theme name -> snapshot (false: failed to load)
---@return {background: string, groups: table<string, table>, terminal: table<string, string>, set: table<string, table>, follow: table<string, string[]>, problems: string[]}
function M.compose(recipe, snaps)
  local out = {
    background = snaps[recipe.ui].background,
    groups = {},
    terminal = snaps[recipe.terminal].terminal or {},
    set = {},
    follow = {},
    problems = {},
  }
  -- group -> theme it came from, to walk that theme's links later
  local source = {}
  for _, slice in ipairs(slices.names) do
    if slice ~= "terminal" then
      local theme = recipe[slice]
      for group, attrs in pairs(snaps[theme].groups) do
        if slices.slice_of(group) == slice then
          out.groups[group] = attrs
          source[group] = theme
        end
      end
    end
  end

  local ov = recipe.overrides
  if not ov then
    return out
  end

  -- group -> "from" | "set": groups overridden by name. set beats from.
  local named = {}
  for _, theme in ipairs(overrides.themes(ov)) do
    local snap = snaps[theme]
    -- A theme that failed to load was already reported; its groups keep slice colors.
    if type(snap) == "table" then
      for _, group in ipairs(ov.from[theme]) do
        if snap.groups[group] then
          out.groups[group] = snap.groups[group]
          named[group] = "from"
        else
          table.insert(
            out.problems,
            string.format("group '%s' not found in theme '%s'", group, theme)
          )
        end
      end
    end
  end
  for group in pairs(ov.set) do
    named[group] = "set"
  end
  out.set = ov.set

  for group, theme in pairs(source) do
    if not named[group] then
      local target = closest_override(group, snaps[theme].links or {}, named)
      if target and named[target] == "set" then
        -- A set value linking to one of its followers would make that follower link to
        -- itself. It keeps its slice attrs and the other followers link to it.
        if ov.set[target].link ~= group then
          out.follow[target] = out.follow[target] or {}
          table.insert(out.follow[target], group)
        end
      elseif target then
        out.groups[group] = out.groups[target]
      end
    end
  end
  for _, followers in pairs(out.follow) do
    table.sort(followers)
  end
  return out
end

return M
