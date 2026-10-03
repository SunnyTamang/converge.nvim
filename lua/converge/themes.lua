---Names of the color schemes the picker offers.
local M = {}

---Theme names in the `colors/` folder of each lazy.nvim plugin. lazy.nvim keeps plugins
---that are not loaded yet off 'runtimepath' and 'packpath', and loads a theme's plugin on
---`ColorSchemePre`, so `getcompletion()` does not see them. Reads lazy.nvim internals, so
---anything unexpected gives an empty list instead of an error.
---@return string[]
function M.lazy_names()
  local lazy = package.loaded["lazy.core.config"]
  if type(lazy) ~= "table" or type(lazy.plugins) ~= "table" then
    return {}
  end
  local names = {}
  for _, plugin in pairs(lazy.plugins) do
    local ok, dir = pcall(function()
      return plugin.dir
    end)
    local handle = ok and type(dir) == "string" and vim.uv.fs_scandir(dir .. "/colors")
    while handle do
      local file = vim.uv.fs_scandir_next(handle)
      if not file then
        break
      end
      local name = file:match("^(.+)%.vim$") or file:match("^(.+)%.lua$")
      if name then
        table.insert(names, name)
      end
    end
  end
  return names
end

---Installed color schemes plus lazy.nvim themes not loaded yet, sorted, without `converge`.
---@return string[]
function M.list()
  local seen, names = { converge = true }, {}
  for _, list in ipairs({ vim.fn.getcompletion("", "color"), M.lazy_names() }) do
    for _, name in ipairs(list) do
      if not seen[name] then
        seen[name] = true
        table.insert(names, name)
      end
    end
  end
  table.sort(names)
  return names
end

return M
