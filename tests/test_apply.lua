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

local function use(recipe)
  child.lua("require('converge').setup({ recipe = ... })", { recipe })
  child.cmd("colorscheme converge")
  H.wait_active(child)
end

T["mixes slices from different themes"] = function()
  use({ ui = "alpha", syntax = "beta", terminal = "gamma" })
  eq(H.hl(child, "Normal"), { fg = H.color(0x10, 1), bg = H.color(0x10, 2) })
  eq(H.hl(child, "Comment"), { fg = H.color(0x20, 3), italic = true })
  eq(H.hl(child, "@string"), { fg = H.color(0x20, 4) })
  -- ui group linked to Comment in its source: keeps alpha's Comment look
  eq(H.hl(child, "CursorLineNr"), { fg = H.color(0x10, 3), italic = true })
  -- slices not in the recipe follow ui
  eq(H.hl(child, "DiagnosticError"), { fg = H.color(0x10, 6) })
  eq(H.hl(child, "DiffAdd"), { bg = H.color(0x10, 7) })
  eq(H.hl(child, "TelescopeNormal"), { fg = H.color(0x10, 9) })
  eq(child.lua_get("vim.g.terminal_color_1"), "#300001")
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(child.lua_get("vim.o.background"), "dark")
end

T["other themes are captured with the ui theme's background"] = function()
  use({ ui = "lightui", syntax = "bgaware" })
  eq(child.lua_get("vim.o.background"), "light")
  eq(H.hl(child, "Comment").fg, H.color(0x50, 3))
end

T["cold cache renders on the next tick, warm cache renders at once"] = function()
  child.lua("require('converge').setup({ recipe = { ui = 'alpha', syntax = 'beta' } })")
  child.lua("vim.cmd.colorscheme('converge'); _G.after = vim.g.colors_name")
  eq(child.lua_get("_G.after") ~= "converge", true)
  H.wait_active(child)

  H.start(child, root)
  child.lua("require('converge').setup({ recipe = { ui = 'alpha', syntax = 'beta' } })")
  child.cmd("colorscheme converge")
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(child.lua_get("vim.g.fixture_loads"), vim.NIL)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
end

T["fires ColorScheme for converge after the mix is rendered"] = function()
  child.lua([[
    _G.events = {}
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function(a)
        table.insert(_G.events, {
          match = a.match,
          comment = vim.api.nvim_get_hl(0, { name = "Comment" }).fg,
        })
      end,
    })
  ]])
  use({ ui = "alpha", syntax = "beta" })
  local events = child.lua_get("_G.events")
  local last = events[#events]
  eq(last.match, "converge")
  eq(last.comment, H.color(0x20, 3))
end

T["a missing slice theme falls back to ui and warns"] = function()
  use({ ui = "alpha", syntax = "nope" })
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("theme 'nope' failed to load", 1, true) ~= nil, true)
end

T["a broken slice theme falls back to ui and warns"] = function()
  use({ ui = "alpha", syntax = "broken" })
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
  eq(H.notes(child)[1].msg:find("theme 'broken' failed to load", 1, true) ~= nil, true)
end

T["a missing ui theme falls back to default"] = function()
  child.cmd("colorscheme default")
  local expected = H.hl(child, "Normal")
  use({ ui = "nope", syntax = "beta" })
  eq(H.hl(child, "Normal"), expected)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
end

T["no setup() uses default"] = function()
  child.cmd("colorscheme default")
  local expected = H.hl(child, "Comment")
  child.cmd("colorscheme converge")
  H.wait_active(child)
  eq(H.hl(child, "Comment"), expected)
end

T["changing 'background' after apply does not loop"] = function()
  use({ ui = "alpha" })
  child.lua("vim.g.fixture_loads = 0")
  child.o.background = "light"
  -- The reload schedules one capture. A loop would schedule another one on every tick.
  H.ticks(child, 3)
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(child.lua_get("vim.o.background"), "light")
  eq(child.lua_get("vim.g.fixture_loads"), 1)
end

T["keeps a group's cterm unset when the source theme had none"] = function()
  child.lua([[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/colors", "p")
    vim.fn.writefile({
      "hi clear",
      "let g:colors_name = 'fidelity'",
      "hi Normal guifg=#112233 guibg=#445566",
      "hi Comment guifg=#112233 gui=italic cterm=NONE",
    }, dir .. "/colors/fidelity.vim")
    vim.opt.rtp:prepend(dir)
  ]])
  use({ ui = "fidelity" })
  local comment = H.hl(child, "Comment")
  eq(comment.italic, true)
  eq(comment.cterm == nil or next(comment.cterm) == nil, true)
end

T["a snapshot that cannot be applied warns instead of throwing"] = function()
  use({ ui = "alpha" })
  child.lua([[
    local jsonfile = require("converge.jsonfile")
    local path = vim.fs.joinpath(require("converge.cache").dir(), "alpha@dark.json")
    local snap = jsonfile.read(path)
    snap.groups.Comment.fg = "not a color"
    jsonfile.write(path, snap)
  ]])
  H.start(child, root)
  child.lua("require('converge').setup({ recipe = { ui = 'alpha' } })")
  eq(child.lua_get("pcall(vim.cmd.colorscheme, 'converge')"), true)
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("could not apply the mix", 1, true) ~= nil, true)
end

T["a pending capture does not override a scheme picked in between"] = function()
  child.lua("require('converge').setup({ recipe = { ui = 'alpha', syntax = 'beta' } })")
  -- Scheduled callbacks run in order, so `ticked` proves the capture callback already ran.
  child.lua([[
    vim.cmd.colorscheme('converge')
    vim.cmd.colorscheme('gamma')
    vim.schedule(function() _G.ticked = true end)
  ]])
  H.wait_for(child, "_G.ticked")
  eq(child.lua_get("vim.g.colors_name"), "gamma")
end

T["a preview where no theme loads still puts 'background' back"] = function()
  child.o.background = "dark"
  child.lua([[
    -- Every capture fails after changing 'background', like a theme that errors halfway.
    require("converge.capture").capture = function()
      vim.g.colors_name = nil
      vim.o.background = "light"
      return nil, "boom"
    end
    require("converge").preview({ ui = "alpha" })
  ]])
  eq(child.lua_get("vim.o.background"), "dark")
  local notes = H.notes(child)
  eq(notes[#notes].msg:find("no theme could be loaded", 1, true) ~= nil, true)
end

T["a cache file without background does not throw at startup"] = function()
  use({ ui = "alpha", syntax = "beta" })
  child.lua([[
    local jsonfile = require("converge.jsonfile")
    local path = vim.fs.joinpath(require("converge.cache").dir(), "alpha@dark.json")
    local snap = jsonfile.read(path)
    snap.background = nil
    jsonfile.write(path, snap)
  ]])
  H.start(child, root)
  child.lua("require('converge').setup({ recipe = { ui = 'alpha', syntax = 'beta' } })")
  eq(child.lua_get("pcall(vim.cmd.colorscheme, 'converge')"), true)
  H.wait_active(child)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
  eq(H.notes(child), {})
end

T["a cache that cannot be written still renders and warns once"] = function()
  child.lua([[
    local dir = require("converge.cache").dir()
    vim.fn.mkdir(dir, "p")
    vim.uv.fs_chmod(dir, tonumber("500", 8))
  ]])
  use({ ui = "alpha", syntax = "beta" })
  child.lua([[vim.uv.fs_chmod(require("converge.cache").dir(), tonumber("700", 8))]])
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("could not write the cache", 1, true) ~= nil, true)
end

return T
