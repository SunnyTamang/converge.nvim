local compose = require("converge.compose")
local config = require("converge.config")
local log = require("converge.log")
local overrides = require("converge.overrides")
local slices = require("converge.slices")
local snapshots = require("converge.snapshots")

local M = {}

---@param opts {recipe?: table}|nil  recipe: slice -> theme name, plus an optional `overrides` table
function M.setup(opts)
  config.setup(opts)
end

---Collect snapshots for a full recipe. A failed theme falls back to the ui theme; a failed
---ui theme falls back to "default".
---@param recipe table every slice filled (may carry `overrides`)
---@param allow_capture boolean
---@param background string 'background' to look up (and capture) the ui theme with
---@return table|nil recipe the final recipe, nil on failure
---@return table|string snaps theme name -> snapshot, or "need_capture" / "failed"
local function collect(recipe, allow_capture, background)
  local opts = { capture = allow_capture }
  recipe = vim.deepcopy(recipe)

  local ui = snapshots.get(recipe.ui, background, opts)
  if ui == false then
    recipe.ui = "default"
    ui = snapshots.get("default", background, opts)
  end
  if ui == nil then
    return nil, "need_capture"
  elseif ui == false then
    return nil, "failed"
  end

  local snaps = { [recipe.ui] = ui }
  for _, slice in ipairs(slices.names) do
    local name = recipe[slice]
    if snaps[name] == nil then
      local snap = snapshots.get(name, ui.background, opts)
      if snap == nil then
        return nil, "need_capture"
      end
      snaps[name] = snap
    end
    if snaps[name] == false then
      recipe[slice] = recipe.ui
    end
  end
  -- Themes used only by overrides.from. A failed one stays `false`; compose skips it.
  for _, name in ipairs(overrides.themes(recipe.overrides)) do
    if snaps[name] == nil then
      local snap = snapshots.get(name, ui.background, opts)
      if snap == nil then
        return nil, "need_capture"
      end
      snaps[name] = snap
    end
  end
  return recipe, snaps
end

---`collect()`, then undo what captures did to 'background', on every exit path.
---@param recipe table every slice filled (may carry `overrides`)
---@param allow_capture boolean
---@param background string|nil base 'background'; nil uses the current one
---@return table|nil recipe
---@return table|string snaps
local function gather(recipe, allow_capture, background)
  background = background or vim.o.background
  local ok, final, snaps = pcall(collect, recipe, allow_capture, background)
  if allow_capture then
    -- Captures changed 'background'. Put it back without reloading any scheme, so the
    -- next apply() looks up the same cache keys.
    vim.g.colors_name = nil
    vim.o.background = background
  end
  if not ok then
    error(final, 0)
  end
  return final, snaps
end

---@param recipe table
---@param snaps table<string, table|false>
local function render_unsafe(recipe, snaps)
  local mixed = compose.compose(recipe, snaps)
  -- Also unsets g:colors_name, so setting 'background' below reloads nothing.
  vim.cmd("hi clear")
  vim.o.background = mixed.background
  for group, attrs in pairs(mixed.groups) do
    vim.api.nvim_set_hl(0, group, attrs)
  end
  -- Your own colors go last, one by one, so one bad value cannot stop the rest. Groups
  -- that linked to an overridden group in their theme follow it.
  for _, group in ipairs(overrides.sorted_keys(mixed.set)) do
    local attrs = mixed.set[group]
    local ok, err = pcall(vim.api.nvim_set_hl, 0, group, attrs)
    if ok then
      for _, follower in ipairs(mixed.follow[group] or {}) do
        vim.api.nvim_set_hl(0, follower, attrs)
      end
    else
      log.warn(string.format("overrides.set: could not apply '%s': %s", group, tostring(err)))
    end
  end
  for _, problem in ipairs(mixed.problems) do
    log.warn("overrides.from: " .. problem)
  end
  for i = 0, 15 do
    vim.g["terminal_color_" .. i] = mixed.terminal[tostring(i)]
  end
  vim.g.colors_name = "converge"
end

---Never throws: a broken snapshot must not break startup.
---@param recipe table
---@param snaps table<string, table|false>
---@return boolean ok
local function render(recipe, snaps)
  local ok, err = pcall(render_unsafe, recipe, snaps)
  if not ok then
    log.warn("could not apply the mix: " .. tostring(err))
  end
  return ok
end

---Entry point of `:colorscheme converge`. Never loads source themes here, because Neovim
---ignores a nested `:colorscheme`. On a cache miss, capture runs on the next loop tick
---and `:colorscheme converge` runs again.
function M.apply()
  local recipe, snaps = gather(config.resolve(), false)
  if recipe then
    return render(recipe, snaps)
  end
  if snaps == "failed" then
    return log.warn("no theme could be loaded, not even 'default'")
  end
  local scheduled_from = vim.g.colors_name
  vim.schedule(function()
    -- The user picked another scheme in between: leave it alone.
    if vim.g.colors_name ~= scheduled_from then
      return
    end
    local ok, final = pcall(gather, config.resolve(), true)
    if not ok then
      return log.warn("could not capture themes: " .. tostring(final))
    end
    if not final then
      return log.warn("no theme could be loaded, not even 'default'")
    end
    vim.cmd.colorscheme("converge")
  end)
end

---Show `recipe` now. Loads source themes if needed. Does not change the saved recipe.
---@param recipe table slice -> theme name, plus an optional `overrides` table
---@param background string|nil base 'background' for the ui theme; nil uses the current one.
---  The picker passes the value from before it opened, since a preview of a theme that
---  forces 'background' changes the current one.
function M.preview(recipe, background)
  local final, snaps = gather(config.complete(recipe), true, background)
  if not final then
    return log.warn("no theme could be loaded, not even 'default'")
  end
  if not render(final, snaps) then
    return
  end
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "converge", modeline = false })
end

---`:Converge [reset|refresh]`. No argument opens the picker.
---@param arg string|nil
function M.command(arg)
  if arg == nil or arg == "" then
    return require("converge.picker").open()
  end
  if arg == "reset" then
    require("converge.store").delete()
  elseif arg == "refresh" then
    require("converge.cache").clear()
    snapshots.clear()
  else
    return vim.notify("converge: unknown subcommand '" .. arg .. "'", vim.log.levels.ERROR)
  end
  if vim.g.colors_name == "converge" then
    vim.cmd.colorscheme("converge")
  end
end

return M
