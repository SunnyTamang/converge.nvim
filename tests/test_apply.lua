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

T["a theme that skips :hi clear does not inherit the previous mix"] = function()
  use({ ui = "alpha" })
  -- converge now holds alpha's @string as plain attributes, not as a link.
  child.lua("require('converge').setup({ recipe = { ui = 'alpha', syntax = 'noclear' } })")
  child.cmd("colorscheme converge")
  H.wait_for(child, 'vim.api.nvim_get_hl(0, { name = "String" }).fg == 0x700004')
  eq(H.hl(child, "@string").fg, 0x700004)
end

T["overrides: from and set go on top of the slices"] = function()
  use({
    ui = "alpha",
    overrides = {
      from = { beta = { "Comment", "Function" } },
      set = { Function = { fg = "#123456" }, MyGroup = { fg = "#abcdef" } },
    },
  })
  eq(H.hl(child, "Comment"), { fg = H.color(0x20, 3), italic = true })
  eq(H.hl(child, "Function"), { fg = 0x123456 })
  eq(H.hl(child, "MyGroup"), { fg = 0xabcdef })
  eq(H.hl(child, "String"), { fg = H.color(0x10, 4) })
  eq(H.notes(child), {})
end

T["overrides: a from theme that is not installed warns, the rest applies"] = function()
  use({ ui = "alpha", overrides = { from = { nope = { "Comment" }, beta = { "String" } } } })
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
  eq(H.hl(child, "String").fg, H.color(0x20, 4))
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("theme 'nope' failed to load", 1, true) ~= nil, true)
end

T["overrides: a from group the theme lacks warns once"] = function()
  use({ ui = "alpha", overrides = { from = { beta = { "Nope" } } } })
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg, "converge: overrides.from: group 'Nope' not found in theme 'beta'")
end

T["overrides: a bad set value warns, other set groups still apply"] = function()
  use({
    ui = "alpha",
    overrides = { set = { Function = { fg = "notacolor" }, MyGroup = { fg = "#abcdef" } } },
  })
  eq(H.hl(child, "MyGroup"), { fg = 0xabcdef })
  eq(H.hl(child, "Function").fg, H.color(0x10, 5))
  eq(child.lua_get("vim.g.colors_name"), "converge")
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("overrides.set: could not apply 'Function'", 1, true) ~= nil, true)
end

T["overrides: from themes use the ui theme's background"] = function()
  use({ ui = "lightui", overrides = { from = { bgaware = { "Comment" } } } })
  eq(H.hl(child, "Comment").fg, H.color(0x50, 3))
end

T["overrides: config overrides apply even when a saved recipe exists"] = function()
  child.lua([[require("converge.store").write({ ui = "alpha" })]])
  use({ ui = "gamma", overrides = { from = { beta = { "Comment" } } } })
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
end

T["overrides: cold cache loads from themes on the next tick"] = function()
  child.lua([[require("converge").setup({ recipe = {
    ui = "alpha", overrides = { from = { beta = { "Comment" } } },
  } })]])
  child.lua("vim.cmd.colorscheme('converge'); _G.after = vim.g.colors_name")
  eq(child.lua_get("_G.after") ~= "converge", true)
  H.wait_active(child)
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
end

T["overrides: refresh captures from themes again"] = function()
  use({ ui = "alpha", overrides = { from = { beta = { "Comment" } } } })
  child.lua("vim.g.fixture_loads = 0")
  child.cmd("Converge refresh")
  H.wait_for(child, "(vim.g.fixture_loads or 0) >= 2")
  eq(child.lua_get("vim.g.fixture_loads"), 2)
  eq(child.lua_get("vim.g.colors_name"), "converge")
  eq(H.hl(child, "Normal").fg, H.color(0x10, 1))
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
end

T["overrides: groups linking to a from group follow it"] = function()
  use({ ui = "alpha", overrides = { from = { beta = { "Comment" } } } })
  for _, group in ipairs({ "Comment", "@comment", "@lsp.type.comment", "CursorLineNr" }) do
    eq(H.hl(child, group).fg, H.color(0x20, 3))
  end
end

T["overrides: groups linking to a set group follow it"] = function()
  use({ ui = "alpha", overrides = { set = { Comment = { fg = "#123456" } } } })
  for _, group in ipairs({ "Comment", "@comment", "@lsp.type.comment", "CursorLineNr" }) do
    eq(H.hl(child, group).fg, 0x123456)
  end
end

T["overrides: the closest override on a link chain wins"] = function()
  use({
    ui = "alpha",
    overrides = { from = { beta = { "Comment" } }, set = { ["@comment"] = { fg = "#123456" } } },
  })
  eq(H.hl(child, "Comment").fg, H.color(0x20, 3))
  eq(H.hl(child, "@comment").fg, 0x123456)
  eq(H.hl(child, "@lsp.type.comment").fg, 0x123456)
  eq(H.hl(child, "CursorLineNr").fg, H.color(0x20, 3))
end

T["overrides: a set link to one of its own followers keeps that follower's colors"] = function()
  use({ ui = "alpha", overrides = { set = { Comment = { link = "@comment" } } } })
  eq(H.hl(child, "@comment").fg, H.color(0x10, 3))
  eq(H.hl(child, "@lsp.type.comment").fg, H.color(0x10, 3))
  eq(H.hl(child, "Comment").fg, H.color(0x10, 3))
  eq(#H.notes(child), 0)
end

T["overrides: a bad set value leaves its followers alone"] = function()
  use({ ui = "alpha", overrides = { set = { Comment = { fg = "notacolor" } } } })
  eq(H.hl(child, "@lsp.type.comment").fg, H.color(0x10, 3))
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].msg:find("overrides.set: could not apply 'Comment'", 1, true) ~= nil, true)
end

return T
