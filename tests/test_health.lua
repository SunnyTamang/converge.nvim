local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      H.start(child)
      child.o.termguicolors = true
    end,
    post_once = child.stop,
  },
})

-- Output of :checkhealth converge, one string.
local function health()
  child.cmd("checkhealth converge")
  return table.concat(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), "\n")
end

local function has(text, needle)
  return text:find(needle, 1, true) ~= nil
end

local function use(recipe)
  child.lua("require('converge').setup({ recipe = ... })", { recipe })
  child.cmd("colorscheme converge")
  H.wait_active(child)
end

T["a good setup has no warnings or errors"] = function()
  use({ ui = "alpha", syntax = "beta", overrides = { from = { gamma = { "Comment" } } } })
  local out = health()
  eq(has(out, "WARNING"), false)
  eq(has(out, "ERROR"), false)
  eq(has(out, "theme 'alpha' is installed"), true)
  eq(has(out, "theme 'gamma' is installed"), true)
  eq(has(out, "overrides: 1 from, 0 set"), true)
  eq(has(out, "converge is the active colorscheme"), true)
end

T["a missing theme is a warning"] = function()
  use({ ui = "alpha", syntax = "nope" })
  eq(has(health(), "WARNING theme 'nope' is not installed"), true)
end

T["converge not active is a warning with the fix"] = function()
  child.lua("require('converge').setup({ recipe = { ui = 'alpha' } })")
  child.cmd("colorscheme gamma")
  local out = health()
  eq(has(out, "WARNING converge is not the active colorscheme (it is 'gamma')"), true)
  eq(has(out, 'vim.cmd.colorscheme("converge")'), true)
end

T["setup() not called is a warning"] = function()
  eq(has(health(), "WARNING setup() was not called"), true)
end

T["a broken saved recipe is an error"] = function()
  child.lua([[
    local path = require("converge.store").path()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ "{ not json" }, path)
  ]])
  use({ ui = "alpha" })
  eq(has(health(), "ERROR saved recipe is broken"), true)
end

T["a saved recipe is reported"] = function()
  child.lua([[require("converge.store").write({ ui = "beta" })]])
  use({ ui = "alpha" })
  eq(has(health(), "slices come from the saved recipe"), true)
end

T["termguicolors off is a warning"] = function()
  use({ ui = "alpha" })
  child.o.termguicolors = false
  eq(has(health(), "WARNING 'termguicolors' is off"), true)
end

T["checkhealth does not change the colors"] = function()
  use({ ui = "alpha", syntax = "beta" })
  local before = H.hl(child, "Comment")
  child.lua("vim.g.fixture_loads = 0")
  health()
  eq(child.lua_get("vim.g.fixture_loads"), 0)
  eq(H.hl(child, "Comment"), before)
end

return T
