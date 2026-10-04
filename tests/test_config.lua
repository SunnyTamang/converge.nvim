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

local function warnings()
  return vim.tbl_map(function(n)
    return n.msg
  end, H.notes(child))
end

T["validate() keeps known slices with string themes"] = function()
  local clean = child.lua_get([[require("converge.config").validate(
    { ui = "alpha", syntax = "beta", colors = "x", git = 3, terminal = "", plugins = "converge" },
    "setup")]])
  eq(clean, { ui = "alpha", syntax = "beta" })
  eq(warnings(), {
    "converge: setup: unknown slice 'colors' ignored",
    "converge: setup: theme for 'git' must be a non-empty string",
    "converge: setup: theme for 'plugins' cannot be 'converge'",
    "converge: setup: theme for 'terminal' must be a non-empty string",
  })
end

T["validate() rejects a non-table"] = function()
  eq(child.lua_get([[require("converge.config").validate("alpha", "setup")]]), {})
  eq(warnings(), { "converge: setup: recipe must be a table" })
end

T["complete() fills missing slices from ui"] = function()
  eq(child.lua_get([[require("converge.config").complete({ ui = "alpha", syntax = "beta" })]]), {
    ui = "alpha",
    syntax = "beta",
    diagnostics = "alpha",
    git = "alpha",
    terminal = "alpha",
    plugins = "alpha",
  })
end

T["complete() uses default when ui is missing"] = function()
  eq(child.lua_get([[require("converge.config").complete({ syntax = "beta" })]]).ui, "default")
end

T["resolve() uses setup() recipe"] = function()
  child.lua([[require("converge").setup({ recipe = { ui = "alpha", syntax = "beta" } })]])
  local r = child.lua_get([[require("converge.config").resolve()]])
  eq({ r.ui, r.syntax, r.git }, { "alpha", "beta", "alpha" })
end

T["resolve() prefers the saved recipe"] = function()
  child.lua([[require("converge").setup({ recipe = { ui = "alpha", syntax = "beta" } })]])
  child.lua([[require("converge.store").write({ ui = "gamma" })]])
  local r = child.lua_get([[require("converge.config").resolve()]])
  eq({ r.ui, r.syntax }, { "gamma", "gamma" })
end

T["resolve() ignores a broken saved recipe"] = function()
  child.lua([[require("converge").setup({ recipe = { ui = "alpha" } })]])
  child.lua([[
    local path = require("converge.store").path()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ "{ not json" }, path)
  ]])
  eq(child.lua_get([[require("converge.config").resolve()]]).ui, "alpha")
  eq(#warnings(), 1)
  MiniTest.expect.equality(warnings()[1]:find("saved recipe is broken", 1, true) ~= nil, true)
end

T["store delete() removes the file"] = function()
  child.lua([[require("converge.store").write({ ui = "alpha" })]])
  child.lua([[require("converge.store").delete()]])
  eq(child.lua_get([[{ require("converge.store").read() }]]), {})
end

T["to_lua() round-trips"] = function()
  local text = child.lua_get([[require("converge.config").to_lua(
    require("converge.config").complete({ ui = "alpha", syntax = "beta" }))]])
  local loaded = loadstring("return {" .. text .. "}")()
  eq(loaded.recipe.ui, "alpha")
  eq(loaded.recipe.syntax, "beta")
  eq(vim.startswith(text, 'recipe = {\n  ui = "alpha",'), true)
end

T["log warns once per message"] = function()
  child.lua([[
    local log = require("converge.log")
    log.warn("same")
    log.warn("same")
    log.warn("other")
  ]])
  eq(warnings(), { "converge: same", "converge: other" })
end

T["wait_for() returns when true and errors on timeout"] = function()
  child.lua("vim.g.ready = true")
  H.wait_for(child, "vim.g.ready == true")

  local ok, err = pcall(H.wait_for, child, "vim.g.never == true", 20)
  eq(ok, false)
  eq(err:find("timed out waiting for: vim.g.never == true", 1, true) ~= nil, true)
end

T["setup() keeps overrides; resolve() takes them from setup even with a saved recipe"] = function()
  child.lua([[require("converge").setup({ recipe = {
    ui = "alpha", overrides = { from = { beta = { "Comment" } } },
  } })]])
  child.lua([[require("converge.store").write({
    ui = "gamma", overrides = { from = { gamma = { "String" } } },
  })]])
  local r = child.lua_get([[require("converge.config").resolve()]])
  eq(r.ui, "gamma")
  eq(r.syntax, "gamma")
  eq(r.overrides.from, { beta = { "Comment" } })
  eq(warnings(), {})
end

T["slices_of() drops overrides"] = function()
  local s = child.lua_get(
    [[require("converge.config").slices_of(
    require("converge.config").complete({ ui = "alpha", overrides = { from = { beta = { "Comment" } } } }))]]
  )
  eq(s.overrides, nil)
  eq(s.ui, "alpha")
  eq(s.plugins, "alpha")
end

T["to_lua() round-trips overrides"] = function()
  local text = child.lua_get([[require("converge.config").to_lua(
    require("converge.config").complete({
      ui = "alpha",
      overrides = {
        from = { ["kanagawa-dragon"] = { "Comment", "@comment" } },
        set = { Visual = { bg = "#2d4f67" }, ["@string"] = { fg = "#ffffff", italic = true } },
      },
    }))]])
  local loaded = loadstring("return {" .. text .. "}")()
  eq(loaded.recipe.ui, "alpha")
  eq(loaded.recipe.overrides.from["kanagawa-dragon"], { "Comment", "@comment" })
  eq(loaded.recipe.overrides.set.Visual, { bg = "#2d4f67" })
  eq(loaded.recipe.overrides.set["@string"], { fg = "#ffffff", italic = true })
end

return T
