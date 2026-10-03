local compose = require("converge.compose")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- A fake snapshot. Every value is `base + n` so the source theme is easy to see.
local function snap(name, base, background)
  return {
    name = name,
    background = background or "dark",
    groups = {
      Normal = { fg = base + 1 },
      Comment = { fg = base + 2 },
      DiagnosticError = { fg = base + 3 },
      DiffAdd = { fg = base + 4 },
      TelescopeNormal = { fg = base + 5 },
    },
    terminal = { ["0"] = name, ["15"] = name },
  }
end

T["takes each slice from its theme"] = function()
  local a, b, c = snap("a", 100, "light"), snap("b", 200), snap("c", 300)
  local recipe = {
    ui = "a",
    syntax = "b",
    diagnostics = "a",
    git = "c",
    terminal = "b",
    plugins = "c",
  }
  local out = compose.compose(recipe, { a = a, b = b, c = c })
  eq(out.background, "light")
  eq(out.groups, {
    Normal = { fg = 101 },
    Comment = { fg = 202 },
    DiagnosticError = { fg = 103 },
    DiffAdd = { fg = 304 },
    TelescopeNormal = { fg = 305 },
  })
  eq(out.terminal, { ["0"] = "b", ["15"] = "b" })
end

T["skips groups the slice theme does not have"] = function()
  local a, b = snap("a", 100), snap("b", 200)
  b.groups.StatusLine = { fg = 299 } -- ui group, but ui comes from a
  a.groups.Normal = nil
  local recipe = {
    ui = "a",
    syntax = "b",
    diagnostics = "a",
    git = "a",
    terminal = "a",
    plugins = "a",
  }
  local out = compose.compose(recipe, { a = a, b = b })
  eq(out.groups.StatusLine, nil)
  eq(out.groups.Normal, nil)
end

T["missing terminal colors give an empty table"] = function()
  local a = snap("a", 100)
  a.terminal = nil
  local recipe = {
    ui = "a",
    syntax = "a",
    diagnostics = "a",
    git = "a",
    terminal = "a",
    plugins = "a",
  }
  eq(compose.compose(recipe, { a = a }).terminal, {})
end

return T
