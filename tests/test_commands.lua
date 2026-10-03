local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      H.start(child)
    end,
    post_once = child.stop,
  },
})

T["reset deletes the saved recipe and re-applies"] = function()
  child.lua([[require("converge.store").write({ ui = "alpha", syntax = "beta" })]])
  child.lua([[require("converge").setup({ recipe = { ui = "alpha", syntax = "gamma" } })]])
  child.cmd("colorscheme converge")
  H.wait_active(child)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))

  child.cmd("Converge reset")
  H.wait_for(
    child,
    string.format('vim.api.nvim_get_hl(0, { name = "Comment" }).fg == %d', H.color(0x30, 3))
  )
  eq(child.lua_get([[vim.uv.fs_stat(require("converge.store").path())]]), vim.NIL)
  eq(H.hl(child, "Comment").fg, H.color(0x30, 3))
end

T["refresh drops the cache and captures again"] = function()
  child.lua([[require("converge").setup({ recipe = { ui = "alpha" } })]])
  child.cmd("colorscheme converge")
  H.wait_active(child)
  child.lua("vim.g.fixture_loads = 0")

  child.cmd("Converge refresh")
  H.wait_for(child, "(vim.g.fixture_loads or 0) > 0")
  H.wait_active(child)
  eq(child.lua_get("vim.g.fixture_loads"), 1)
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
end

T["reset when converge is not active only deletes the file"] = function()
  child.lua([[require("converge.store").write({ ui = "alpha" })]])
  child.cmd("colorscheme gamma")
  child.cmd("Converge reset")
  eq(child.lua_get("vim.g.colors_name"), "gamma")
  eq(child.lua_get([[vim.uv.fs_stat(require("converge.store").path())]]), vim.NIL)
end

T["unknown subcommand is an error message"] = function()
  child.cmd("Converge nope")
  local notes = H.notes(child)
  eq(notes[1].msg, "converge: unknown subcommand 'nope'")
  eq(notes[1].level, vim.log.levels.ERROR)
end

T["completion lists subcommands"] = function()
  eq(child.lua_get([[vim.fn.getcompletion("Converge ", "cmdline")]]), { "refresh", "reset" })
end

return T
