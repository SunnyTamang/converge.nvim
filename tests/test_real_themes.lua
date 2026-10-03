local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
local DEPS = { "deps/tokyonight.nvim", "deps/catppuccin", "deps/gruvbox.nvim" }

local T = MiniTest.new_set({ hooks = { post_once = child.stop } })

T["mixes tokyonight, catppuccin and gruvbox"] = function()
  for _, dir in ipairs(DEPS) do
    if vim.fn.isdirectory(dir) == 0 then
      MiniTest.skip("run `make deps-real` first")
    end
  end
  H.start(child)
  child.lua(
    [[for _, dir in ipairs(...) do vim.opt.rtp:append(vim.fn.getcwd() .. "/" .. dir) end]],
    { DEPS }
  )

  -- Each theme alone, dark background.
  child.o.background = "dark"
  child.cmd("colorscheme tokyonight-night")
  local normal = H.hl(child, "Normal")
  child.cmd("colorscheme catppuccin-mocha")
  local comment = H.hl(child, "Comment")
  local func = H.hl(child, "@function")
  child.o.background = "dark"
  child.cmd("colorscheme gruvbox")
  local term1 = child.lua_get("vim.g.terminal_color_1")

  child.o.background = "dark"
  child.lua([[require("converge").setup({ recipe = {
    ui = "tokyonight-night", syntax = "catppuccin-mocha", terminal = "gruvbox",
  } })]])
  child.cmd("colorscheme converge")
  H.wait_active(child)

  eq(H.hl(child, "Normal"), normal)
  eq(H.hl(child, "Comment"), comment)
  eq(H.hl(child, "@function"), func)
  eq(child.lua_get("vim.g.terminal_color_1"), term1)
  eq(H.notes(child), {})
end

return T
