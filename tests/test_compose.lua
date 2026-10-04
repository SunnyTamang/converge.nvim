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

local function all(theme)
  return {
    ui = theme,
    syntax = theme,
    diagnostics = theme,
    git = theme,
    terminal = theme,
    plugins = theme,
  }
end

T["no overrides: empty set and problems"] = function()
  local out = compose.compose(all("a"), { a = snap("a", 100) })
  eq(out.set, {})
  eq(out.problems, {})
end

T["from replaces slice groups and set is passed through"] = function()
  local recipe = all("a")
  recipe.overrides = {
    from = { b = { "Comment", "Normal" } },
    set = { Comment = { fg = 999 } },
  }
  local out = compose.compose(recipe, { a = snap("a", 100), b = snap("b", 200) })
  eq(out.groups.Comment, { fg = 202 })
  eq(out.groups.Normal, { fg = 201 })
  eq(out.groups.DiffAdd, { fg = 104 })
  eq(out.set, { Comment = { fg = 999 } })
  eq(out.problems, {})
end

T["a missing from group is a problem and keeps the slice color"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Nope", "Comment" } }, set = {} }
  local out = compose.compose(recipe, { a = snap("a", 100), b = snap("b", 200) })
  eq(out.groups.Comment, { fg = 202 })
  eq(out.groups.Nope, nil)
  eq(out.problems, { "group 'Nope' not found in theme 'b'" })
end

T["a from theme that failed to load is skipped"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = {} }
  local out = compose.compose(recipe, { a = snap("a", 100), b = false })
  eq(out.groups.Comment, { fg = 102 })
  eq(out.problems, {})
end

-- A snapshot with a kanagawa-like comment chain:
-- @lsp.type.comment -> @comment -> Comment, and CursorLineNr (ui) -> Comment.
local function linked(name, base)
  local s = snap(name, base)
  s.groups["@comment"] = { fg = base + 2 }
  s.groups["@lsp.type.comment"] = { fg = base + 2 }
  s.groups.CursorLineNr = { fg = base + 2 }
  s.links = {
    ["@comment"] = "Comment",
    ["@lsp.type.comment"] = "@comment",
    CursorLineNr = "Comment",
  }
  return s
end

T["no overrides: nothing follows"] = function()
  local out = compose.compose(all("a"), { a = linked("a", 100) })
  eq(out.follow, {})
  eq(out.groups["@lsp.type.comment"], { fg = 102 })
end

T["groups linking to a from group follow it, across slices too"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = {} }
  local out = compose.compose(recipe, { a = linked("a", 100), b = snap("b", 200) })
  eq(out.groups.Comment, { fg = 202 })
  eq(out.groups["@comment"], { fg = 202 })
  eq(out.groups["@lsp.type.comment"], { fg = 202 })
  eq(out.groups.CursorLineNr, { fg = 202 })
  eq(out.follow, {})
end

T["the closest overridden group on the chain wins"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = { ["@comment"] = { fg = 999 } } }
  local out = compose.compose(recipe, { a = linked("a", 100), b = snap("b", 200) })
  eq(out.follow, { ["@comment"] = { "@lsp.type.comment" } })
  eq(out.groups.CursorLineNr, { fg = 202 })
  eq(out.groups["@lsp.type.comment"], { fg = 102 }) -- render applies the set value
end

T["a group named in overrides never follows"] = function()
  local recipe = all("a")
  recipe.overrides = {
    from = { b = { "Comment" } },
    set = { ["@lsp.type.comment"] = { fg = 5 } },
  }
  local out = compose.compose(recipe, { a = linked("a", 100), b = snap("b", 200) })
  eq(out.groups["@comment"], { fg = 202 })
  eq(out.groups["@lsp.type.comment"], { fg = 102 })
  eq(out.follow, {})
end

T["set beats from on the same group, also for followers"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = { Comment = { fg = 7 } } }
  local out = compose.compose(recipe, { a = linked("a", 100), b = snap("b", 200) })
  eq(out.follow, { Comment = { "@comment", "@lsp.type.comment", "CursorLineNr" } })
  eq(out.groups["@comment"], { fg = 102 })
end

T["a set link to one of its own followers keeps that follower's slice"] = function()
  local recipe = all("a")
  recipe.overrides = { from = {}, set = { Comment = { link = "@comment" } } }
  local out = compose.compose(recipe, { a = linked("a", 100) })
  eq(out.follow.Comment, { "@lsp.type.comment", "CursorLineNr" })
end

T["follow uses the links of the theme the group came from"] = function()
  local a = snap("a", 100)
  a.groups["@comment"] = { fg = 102 }
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = {} }
  local out = compose.compose(recipe, { a = a, b = snap("b", 200) })
  eq(out.groups.Comment, { fg = 202 })
  eq(out.groups["@comment"], { fg = 102 })
end

T["a missing from target is not an override, so followers keep the slice"] = function()
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Nope" } }, set = {} }
  local out = compose.compose(recipe, { a = linked("a", 100), b = snap("b", 200) })
  eq(out.groups["@comment"], { fg = 102 })
  eq(out.follow, {})
end

T["a link cycle stops"] = function()
  local a = linked("a", 100)
  a.groups.X = { fg = 1 }
  a.groups.Y = { fg = 2 }
  a.links.X = "Y"
  a.links.Y = "X"
  local recipe = all("a")
  recipe.overrides = { from = { b = { "Comment" } }, set = {} }
  local out = compose.compose(recipe, { a = a, b = snap("b", 200) })
  eq(out.groups.X, { fg = 1 })
  eq(out.groups.Y, { fg = 2 })
end

return T
