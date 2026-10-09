---`:checkhealth converge`. Only reads state: never loads a theme or changes colors.
local cache = require("converge.cache")
local config = require("converge.config")
local overrides = require("converge.overrides")
local slices = require("converge.slices")
local store = require("converge.store")
local themes = require("converge.themes")

local M = {}

local health = vim.health

---Slices from the saved recipe if there is one, else from setup(). Same rule as
---config.resolve(), but without warnings.
---@return table recipe every slice filled
---@return boolean from_saved
local function active_recipe()
  local saved = store.read()
  local base = type(saved) == "table" and saved or config.options.recipe
  return config.complete(base), type(saved) == "table"
end

---Theme names used by the recipe, slices first, then overrides.from, without repeats.
local function used_themes(recipe)
  local names, seen = {}, {}
  local function add(name)
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  for _, slice in ipairs(slices.names) do
    add(recipe[slice])
  end
  for _, name in ipairs(overrides.themes(config.options.recipe.overrides)) do
    add(name)
  end
  return names
end

local function check_setup()
  health.start("converge: setup")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or newer is required")
  end

  if config.configured then
    health.ok("setup() was called")
  else
    health.warn("setup() was not called", {
      'Call require("converge").setup({ recipe = { ... } }) before',
      'vim.cmd.colorscheme("converge"). Without it the "default" theme is used.',
    })
  end

  local saved, err = store.read()
  if err then
    health.error("saved recipe is broken: " .. store.path(), {
      "Run :Converge reset to delete it, or save a new one in the picker.",
    })
  elseif saved then
    health.info("slices come from the saved recipe: " .. store.path())
    health.info("Run :Converge reset to use the slices from setup() again.")
  else
    health.info("slices come from setup()")
  end

  if vim.g.colors_name == "converge" then
    health.ok("converge is the active colorscheme")
  else
    health.warn(
      ("converge is not the active colorscheme (it is '%s')"):format(tostring(vim.g.colors_name)),
      { 'Add vim.cmd.colorscheme("converge") after setup(), and remove other colorscheme calls.' }
    )
  end

  if vim.o.termguicolors then
    health.ok("'termguicolors' is on")
  else
    health.warn("'termguicolors' is off: colors are only approximate", {
      "Add vim.o.termguicolors = true to your config.",
    })
  end
end

local function check_themes(recipe)
  health.start("converge: themes")
  local installed = {}
  for _, name in ipairs(themes.list()) do
    installed[name] = true
  end
  installed.default = true
  for _, name in ipairs(used_themes(recipe)) do
    if installed[name] then
      health.ok(("theme '%s' is installed"):format(name))
    else
      health.warn(("theme '%s' is not installed"):format(name), {
        "Install it, or fix the name in the recipe. Check names with :colorscheme <Tab>.",
      })
    end
  end
  local from_n, set_n = overrides.counts(config.options.recipe.overrides)
  health.info(("overrides: %d from, %d set"):format(from_n, set_n))
end

local function check_cache(recipe)
  health.start("converge: cache")
  local dir = cache.dir()
  local target = vim.fn.isdirectory(dir) == 1 and dir or vim.fs.dirname(dir)
  if vim.fn.filewritable(target) == 2 then
    health.ok("cache folder can be written: " .. dir)
  else
    health.error("cache folder cannot be written: " .. dir, {
      "Without a cache, every theme is read again at each start.",
    })
  end
  for _, name in ipairs(used_themes(recipe)) do
    if cache.read(name, vim.o.background) then
      health.info(("'%s' is cached"):format(name))
    else
      health.info(("'%s' is not cached yet: it is read on the next start"):format(name))
    end
  end
end

function M.check()
  local recipe = active_recipe()
  check_setup()
  check_themes(recipe)
  check_cache(recipe)
end

return M
