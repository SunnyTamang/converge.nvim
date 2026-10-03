local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      root = H.start(child)
    end,
    post_once = child.stop,
  },
})

local INSTALLED = [[vim.tbl_filter(function(n)
  return n ~= "converge"
end, vim.fn.getcompletion("", "color"))]]

local function list()
  return child.lua_get([[require("converge.themes").list()]])
end

-- A plugin folder that is not on 'runtimepath', like a theme lazy.nvim has not loaded yet.
local function plugin_dir(name, files)
  local dir = root .. "/lazy/" .. name
  vim.fn.mkdir(dir .. "/colors", "p")
  for _, file in ipairs(files) do
    vim.fn.writefile({ "" }, dir .. "/colors/" .. file)
  end
  return dir
end

-- Pretend lazy.nvim is loaded, with `plugins` as its plugin table.
local function fake_lazy(plugins)
  child.lua([[package.loaded["lazy.core.config"] = { plugins = ... }]], { plugins })
end

T["without lazy.nvim lists the installed themes except converge"] = function()
  local names = list()
  eq(names, child.lua_get(INSTALLED))
  eq(vim.tbl_contains(names, "alpha"), true)
  eq(vim.tbl_contains(names, "converge"), false)
end

T["adds themes of lazy.nvim plugins that are not loaded yet"] = function()
  fake_lazy({
    ["lazytheme.nvim"] = {
      dir = plugin_dir("lazytheme.nvim", {
        "lazytheme.lua",
        "lazytheme-day.vim",
        "converge.lua",
        "notes.txt",
      }),
    },
    -- Already on 'rtp': must not be listed twice.
    ["fixtures"] = { dir = vim.fn.getcwd() .. "/tests/fixtures" },
    ["no-colors"] = { dir = root .. "/lazy/missing" },
    ["no-dir"] = {},
  })
  local names = list()
  local expected = child.lua_get(INSTALLED)
  vim.list_extend(expected, { "lazytheme", "lazytheme-day" })
  table.sort(expected)
  eq(names, expected)
end

T["odd lazy.nvim internals do not break the list"] = function()
  local installed = child.lua_get(INSTALLED)
  for _, value in ipairs({
    "true",
    "{}",
    "{ plugins = 'nope' }",
    "{ plugins = { 'x', { dir = 3 } } }",
    [[{ plugins = { setmetatable({}, { __index = function() error("boom") end }) } }]],
  }) do
    child.lua([[package.loaded["lazy.core.config"] = ]] .. value)
    eq(list(), installed)
  end
  eq(H.notes(child), {})
end

return T
