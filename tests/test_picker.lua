local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()
local root

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      root = H.start(child)
      child.lua([[require("converge").setup({ recipe = { ui = "alpha" } })]])
      child.cmd("colorscheme converge")
      H.wait_active(child)
    end,
    post_once = child.stop,
  },
})

local FLOAT_COUNT = [[#vim.tbl_filter(function(w)
  return vim.api.nvim_win_get_config(w).relative ~= ""
end, vim.api.nvim_list_wins())]]

local function float_count()
  return child.lua_get(FLOAT_COUNT)
end

local function lines()
  return child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
end

-- Footer text of the current (picker) window.
local function footer()
  return child.lua_get([[(function()
    local parts = {}
    for _, chunk in ipairs(vim.api.nvim_win_get_config(0).footer or {}) do
      table.insert(parts, chunk[1])
    end
    return table.concat(parts)
  end)()]])
end

-- Row of `theme` in the theme list.
local function row_of(theme)
  local names = child.lua_get([[require("converge.themes").list()]])
  for i, name in ipairs(names) do
    if name == theme then
      return i
    end
  end
  error("theme not found: " .. theme)
end

-- Open the picker and the syntax theme list, then move to `theme`.
local function pick_syntax(theme)
  child.cmd("Converge")
  child.type_keys("j", "<CR>")
  child.type_keys(row_of(theme) .. "G")
end

T["opens two floats listing slices"] = function()
  child.cmd("Converge")
  eq(float_count(), 2)
  local l = lines()
  eq(#l, 6)
  eq(l[1]:match("^%s*ui%s+alpha$") ~= nil, true)
  eq(l[2]:match("^%s*syntax%s+alpha$") ~= nil, true)
end

T["moving in the theme list previews live"] = function()
  pick_syntax("beta")
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
end

T["<Esc> in the theme list undoes the preview"] = function()
  pick_syntax("beta")
  child.type_keys("<Esc>")
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
  eq(lines()[2]:match("^%s*syntax%s+alpha$") ~= nil, true)
end

T["<CR> keeps the theme, s saves, q closes"] = function()
  pick_syntax("beta")
  child.type_keys("<CR>")
  eq(lines()[2]:match("^%s*syntax%s+beta$") ~= nil, true)
  child.type_keys("s", "q")
  eq(float_count(), 0)
  eq(child.lua_get([[require("converge.store").read()]]).syntax, "beta")
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))

  -- A new session uses the saved recipe over the one in setup().
  H.start(child, root)
  child.lua([[require("converge").setup({ recipe = { ui = "alpha" } })]])
  child.cmd("colorscheme converge")
  H.wait_active(child)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
end

T["q without saving undoes changes"] = function()
  pick_syntax("beta")
  child.type_keys("<CR>", "q")
  eq(float_count(), 0)
  eq(child.lua_get([[require("converge.store").read()]]), vim.NIL)
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
end

T["q restores a non-converge scheme when nothing was saved"] = function()
  child.cmd("colorscheme gamma")
  child.cmd("Converge")
  child.type_keys("q")
  eq(child.lua_get("vim.g.colors_name"), "gamma")
end

T["y copies the recipe as Lua"] = function()
  pick_syntax("beta")
  child.type_keys("<CR>", "y")
  local text = child.lua_get([[vim.fn.getreg('"')]])
  local loaded = loadstring("return {" .. text .. "}")()
  eq(loaded.recipe.syntax, "beta")
  eq(loaded.recipe.ui, "alpha")
end

T["preview shows terminal colors"] = function()
  child.cmd("Converge")
  local bg = child.lua_get([[vim.api.nvim_get_hl(require("converge.preview").hl_ns,
    { name = "ConvergeTerm1" }).bg]])
  eq(bg, 0x100001)
end

T["closing the window with :close cleans up"] = function()
  child.cmd("Converge")
  child.cmd("close")
  H.wait_for(child, "(" .. FLOAT_COUNT .. ") == 0")
  eq(float_count(), 0)
  child.cmd("Converge")
  eq(float_count(), 2)
end

T["<Esc> in the slice list closes"] = function()
  child.cmd("Converge")
  child.type_keys("<Esc>")
  eq(float_count(), 0)
end

T["q with no previous scheme restores default"] = function()
  H.start(child)
  child.lua([[require("converge").setup({ recipe = { ui = "alpha" } })]])
  eq(child.lua_get("vim.g.colors_name"), vim.NIL)
  child.cmd("Converge")
  child.type_keys("q")
  eq(float_count(), 0)
  eq(child.lua_get("vim.g.colors_name"), "default")
end

T[":Converge while open focuses the existing picker"] = function()
  child.cmd("Converge")
  local win = child.lua_get("vim.api.nvim_get_current_win()")
  child.cmd("wincmd p")
  child.cmd("Converge")
  eq(float_count(), 2)
  eq(child.lua_get("vim.api.nvim_get_current_win()"), win)
end

T["close then reopen in one tick keeps the new picker"] = function()
  child.cmd("Converge")
  child.lua([[
    require("converge.picker").close()
    require("converge.picker").open()
  ]])
  -- Let the stale WinClosed callback run.
  child.lua([[_G.ticked = false; vim.schedule(function() _G.ticked = true end)]])
  H.wait_for(child, "_G.ticked")
  eq(float_count(), 2)
end

T["a failed open does not break later opens"] = function()
  child.lua([[
    local orig = vim.api.nvim_open_win
    local calls = 0
    vim.api.nvim_open_win = function(...)
      calls = calls + 1
      if calls == 2 then
        vim.api.nvim_open_win = orig
        error("boom")
      end
      return orig(...)
    end
  ]])
  child.cmd("Converge")
  eq(float_count(), 0)
  eq(
    child.lua_get(
      [[#vim.tbl_filter(function(n) return n.msg:find("cannot open picker") end, _G.notes)]]
    ),
    1
  )
  child.cmd("Converge")
  eq(float_count(), 2)
end

T["an unlisted current theme is not previewed on open"] = function()
  child.lua([[
    local converge = require("converge")
    local config = require("converge.config")
    local resolve = config.resolve
    config.resolve = function(...)
      local r = resolve(...)
      r.syntax = "not-a-theme"
      return r
    end
    _G.previews = 0
    converge.preview = function()
      _G.previews = _G.previews + 1
    end
  ]])
  child.cmd("Converge")
  child.type_keys("j", "<CR>")
  child.lua([[_G.ticked = false; vim.schedule(function() _G.ticked = true end)]])
  H.wait_for(child, "_G.ticked")
  eq(child.lua_get("_G.previews"), 1) -- the initial render only
  eq(child.lua_get("vim.api.nvim_win_get_cursor(0)[1]"), 1)
end

T["q after previewing a light-forcing theme restores the old scheme and background"] = function()
  H.start(child)
  child.o.background = "dark"
  child.cmd("colorscheme bgaware")
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
  child.cmd("Converge")
  child.type_keys("<CR>") -- ui slice
  child.type_keys(row_of("lightui") .. "G")
  eq(child.lua_get("vim.o.background"), "light")
  -- Later previews still capture with the background from before the picker opened.
  child.type_keys(row_of("bgaware") .. "G")
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
  child.type_keys("<Esc>", "q")
  eq(child.lua_get("vim.g.colors_name"), "bgaware")
  eq(child.lua_get("vim.o.background"), "dark")
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
end

T["<Esc> after previewing a light-forcing ui theme restores the converge look"] = function()
  H.start(child)
  child.o.background = "dark"
  child.lua([[require("converge").setup({ recipe = { ui = "bgaware" } })]])
  child.cmd("colorscheme converge")
  H.wait_active(child)
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
  child.cmd("Converge")
  child.type_keys("<CR>") -- ui slice
  child.type_keys(row_of("lightui") .. "G")
  eq(H.hl(child, "Normal").fg, H.color(0x60, 1))
  child.type_keys("<Esc>")
  eq(child.lua_get("vim.o.background"), "dark")
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
  child.type_keys("q")
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(child.lua_get("vim.o.background"), "dark")
  eq(H.hl(child, "Normal").fg, H.color(0x40, 1))
end

T["a failed save warns and is not treated as saved"] = function()
  child.lua([[
    local dir = vim.fs.dirname(require("converge.store").path())
    vim.fn.mkdir(dir, "p")
    vim.uv.fs_chmod(dir, tonumber("500", 8))
  ]])
  pick_syntax("beta")
  child.type_keys("<CR>", "s")
  child.lua([[
    vim.uv.fs_chmod(vim.fs.dirname(require("converge.store").path()), tonumber("700", 8))
  ]])
  local msgs = vim.tbl_map(function(n)
    return n.msg
  end, H.notes(child))
  eq(#msgs, 1)
  eq(msgs[1]:find("could not save the recipe", 1, true) ~= nil, true)
  child.type_keys("q")
  eq(child.lua_get([[require("converge.store").read()]]), vim.NIL)
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
end

T["lists and previews a theme lazy.nvim has not loaded yet"] = function()
  child.lua([[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/colors", "p")
    vim.fn.writefile(
      { 'require("fixture_theme").define("lazyt", 0x70)' },
      dir .. "/colors/lazyt.lua"
    )
    -- What lazy.nvim does: know the plugin folder, and load it on ColorSchemePre.
    package.loaded["lazy.core.config"] = { plugins = { lazyt = { dir = dir } } }
    vim.api.nvim_create_autocmd("ColorSchemePre", {
      pattern = "lazyt",
      once = true,
      callback = function()
        vim.opt.rtp:append(dir)
      end,
    })
  ]])
  child.cmd("Converge")
  child.type_keys("j", "<CR>")
  local row
  for i, line in ipairs(lines()) do
    if line == "lazyt" then
      row = i
    end
  end
  eq(row ~= nil, true)
  child.type_keys(row .. "G")
  eq(H.notes(child), {})
  eq(H.hl(child, "Comment").fg, H.color(0x70, 3))
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
end

T["picker windows keep their buffers"] = function()
  if child.lua_get([[vim.fn.exists("+winfixbuf")]]) == 0 then
    MiniTest.skip("'winfixbuf' needs Neovim 0.10.1 or newer")
  end
  child.cmd("Converge")
  local fixed = child.lua_get([[vim.tbl_map(function(w)
    return vim.wo[w].winfixbuf
  end, vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative ~= ""
  end, vim.api.nvim_list_wins()))]])
  eq(fixed, { true, true })
end

T["footer shows the keys for each list"] = function()
  child.cmd("Converge")
  eq(footer(), " s save  q quit ")
  child.type_keys("j", "<CR>")
  eq(footer(), " Enter keep  Esc back ")
  child.type_keys("<Esc>")
  eq(footer(), " s save  q quit ")
end

return T
