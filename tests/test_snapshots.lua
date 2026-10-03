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

local function get(name, background, capture)
  return child.lua_get(
    string.format(
      [[require("converge.snapshots").get(%q, %q, { capture = %s })]],
      name,
      background,
      tostring(capture)
    )
  )
end

T["capture resolves links and reads terminal colors"] = function()
  local snap = get("alpha", "dark", true)
  eq(snap.name, "alpha")
  eq(snap.background, "dark")
  eq(snap.version, 3)
  eq(snap.groups.Comment, { fg = H.color(0x10, 3), italic = true, cterm = {} })
  eq(snap.groups["@string"], { fg = H.color(0x10, 4), cterm = {} })
  eq(snap.groups.CursorLineNr, { fg = H.color(0x10, 3), italic = true, cterm = {} })
  eq(snap.terminal["1"], "#100001")
  eq(vim.endswith(snap.source.path, "tests/fixtures/colors/alpha.lua"), true)
end

T["capture sets 'background' before loading"] = function()
  eq(get("bgaware", "light", true).groups.Comment.fg, H.color(0x50, 3))
  eq(get("bgaware", "dark", true).groups.Comment.fg, H.color(0x40, 3))
end

T["capture does not reload the current scheme when setting 'background'"] = function()
  child.cmd("colorscheme gamma")
  child.lua("vim.g.fixture_loads = 0")
  get("alpha", "light", true)
  eq(child.lua_get("vim.g.fixture_loads"), 1)
end

T["without capture, an unknown theme is nil"] = function()
  eq(get("alpha", "dark", false), vim.NIL)
end

T["a failed theme is false and warns once"] = function()
  eq(get("broken", "dark", true), false)
  eq(get("broken", "dark", true), false)
  eq(get("nope", "dark", true), false)
  local notes = H.notes(child)
  eq(#notes, 2)
  eq(notes[1].msg:find("theme 'broken' failed to load", 1, true) ~= nil, true)
  eq(notes[2].msg:find("theme 'nope' failed to load", 1, true) ~= nil, true)
end

T["the disk cache serves a new session without loading the theme"] = function()
  local first = get("alpha", "dark", true)
  H.start(child, root)
  eq(get("alpha", "dark", false), first)
  eq(child.lua_get("vim.g.fixture_loads"), vim.NIL)
end

T["a changed theme file invalidates the cache"] = function()
  local dir = root .. "/rtp"
  local path = dir .. "/colors/tmptheme.lua"
  vim.fn.mkdir(dir .. "/colors", "p")
  vim.fn.writefile({ 'require("fixture_theme").define("tmptheme", 0x70)' }, path)
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  get("tmptheme", "dark", true)

  vim.fn.writefile({ 'require("fixture_theme").define("tmptheme", 0x71)' }, path)
  local later = os.time() + 60
  vim.uv.fs_utime(path, later, later)

  H.start(child, root)
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  eq(get("tmptheme", "dark", false), vim.NIL)
  eq(get("tmptheme", "dark", true).groups.Comment.fg, H.color(0x71, 3))
end

T["a broken or old cache file is a miss"] = function()
  get("alpha", "dark", true)
  child.lua([[
    local cache = require("converge.cache")
    local path = vim.fs.joinpath(cache.dir(), "alpha@dark.json")
    vim.fn.writefile({ "{ broken" }, path)
  ]])
  H.start(child, root)
  eq(get("alpha", "dark", false), vim.NIL)

  get("alpha", "dark", true)
  child.lua([[
    local jsonfile = require("converge.jsonfile")
    local path = vim.fs.joinpath(require("converge.cache").dir(), "alpha@dark.json")
    local snap = jsonfile.read(path)
    snap.version = 0
    jsonfile.write(path, snap)
  ]])
  H.start(child, root)
  eq(get("alpha", "dark", false), vim.NIL)
end

T["cache.clear() and snapshots.clear() forget everything"] = function()
  get("alpha", "dark", true)
  child.lua([[require("converge.cache").clear(); require("converge.snapshots").clear()]])
  eq(get("alpha", "dark", false), vim.NIL)
  eq(child.lua_get([[vim.fn.isdirectory(require("converge.cache").dir())]]), 0)
end

-- Write alpha's dark snapshot back to `file` after `edit` (a Lua chunk given `snap`).
local function corrupt(edit, file)
  child.lua(
    [[
    local edit, file = ...
    local jsonfile = require("converge.jsonfile")
    local dir = require("converge.cache").dir()
    local snap = jsonfile.read(vim.fs.joinpath(dir, "alpha@dark.json"))
    loadstring(edit)(snap)
    jsonfile.write(vim.fs.joinpath(dir, file or "alpha@dark.json"), snap)
  ]],
    { edit, file }
  )
end

local MALFORMED = {
  ["a missing background"] = "local snap = ...; snap.background = nil",
  ["a background that is not dark or light"] = "local snap = ...; snap.background = 'blue'",
  ["groups that are not a table"] = "local snap = ...; snap.groups = 'x'",
  ["terminal colors that are not a table"] = "local snap = ...; snap.terminal = 3",
  ["another theme's name"] = "local snap = ...; snap.name = 'beta'",
}

for what, edit in pairs(MALFORMED) do
  T["a cache file with " .. what .. " is a silent miss and is rewritten"] = function()
    get("alpha", "dark", true)
    corrupt(edit)
    H.start(child, root)
    eq(get("alpha", "dark", false), vim.NIL)
    eq(H.notes(child), {})
    local fresh = get("alpha", "dark", true)
    eq(fresh.name, "alpha")
    H.start(child, root)
    eq(get("alpha", "dark", false), fresh)
  end
end

T["a cache file written for another theme name is a miss"] = function()
  get("alpha", "dark", true)
  -- Same sanitized file name as "other": a snapshot of "alpha" stored there.
  corrupt("", "other@dark.json")
  H.start(child, root)
  eq(get("other", "dark", false), vim.NIL)
end

T["the source file is the one Neovim loads: .vim before .lua"] = function()
  local dir = root .. "/rtp"
  vim.fn.mkdir(dir .. "/colors", "p")
  vim.fn.writefile({ 'require("fixture_theme").define("both", 0x70)' }, dir .. "/colors/both.lua")
  vim.fn.writefile(
    { 'lua require("fixture_theme").define("both", 0x71)' },
    dir .. "/colors/both.vim"
  )
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  local snap = get("both", "dark", true)
  eq(snap.groups.Comment.fg, H.color(0x71, 3))
  eq(vim.endswith(snap.source.path, "/colors/both.vim"), true)
end

T["a theme in an opt package is cached on disk"] = function()
  local pack = root .. "/pack"
  local colors = pack .. "/pack/x/opt/optt/colors"
  vim.fn.mkdir(colors, "p")
  vim.fn.writefile(
    { "hi clear", "let g:colors_name = 'optt'", "hi Normal guifg=#010203" },
    colors .. "/optt.vim"
  )
  child.o.packpath = pack
  local snap = get("optt", "dark", true)
  eq(snap.groups.Normal.fg, 0x010203)
  eq(snap.source.path, colors .. "/optt.vim")

  H.start(child, root)
  child.o.packpath = pack
  eq(get("optt", "dark", false), snap)
end

-- A theme whose colors live in lua/, like most modern themes. Returns the lua/ file.
local function lua_theme(name)
  local dir = root .. "/" .. name
  vim.fn.mkdir(dir .. "/colors", "p")
  vim.fn.mkdir(dir .. "/lua/" .. name, "p")
  vim.fn.writefile(
    { string.format('require("%s.palette")', name) },
    dir .. "/colors/" .. name .. ".lua"
  )
  local palette = dir .. "/lua/" .. name .. "/palette.lua"
  vim.fn.writefile({ string.format('require("fixture_theme").define(%q, 0x70)', name) }, palette)
  return dir, palette
end

T["a changed file in the theme's lua/ directory invalidates the cache"] = function()
  local dir, palette = lua_theme("luatheme")
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  eq(get("luatheme", "dark", true).groups.Comment.fg, H.color(0x70, 3))

  H.start(child, root)
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  eq(get("luatheme", "dark", false) ~= vim.NIL, true)

  vim.fn.writefile({ 'require("fixture_theme").define("luatheme", 0x71)' }, palette)
  local later = os.time() + 60
  vim.uv.fs_utime(palette, later, later)

  H.start(child, root)
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  eq(get("luatheme", "dark", false), vim.NIL)
  eq(get("luatheme", "dark", true).groups.Comment.fg, H.color(0x71, 3))
end

T["a theme without a lua/ directory is cached"] = function()
  local dir = root .. "/plain"
  vim.fn.mkdir(dir .. "/colors", "p")
  vim.fn.writefile({ 'require("fixture_theme").define("plain", 0x70)' }, dir .. "/colors/plain.lua")
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  local snap = get("plain", "dark", true)
  H.start(child, root)
  child.lua("vim.opt.rtp:prepend(...)", { dir })
  eq(get("plain", "dark", false), snap)
end

return T
