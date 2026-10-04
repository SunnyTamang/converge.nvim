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

local function validate(value)
  return child.lua_get("require('converge.overrides').validate(..., 'setup')", { value })
end

local function warnings()
  return vim.tbl_map(function(n)
    return n.msg
  end, H.notes(child))
end

T["validate() keeps valid from and set"] = function()
  local value = {
    from = { nord = { "Comment", "@comment" } },
    set = { Visual = { bg = "#2d4f67" } },
  }
  eq(validate(value), value)
  eq(warnings(), {})
end

T["validate() of nil is nil, without a warning"] = function()
  eq(child.lua_get("require('converge.overrides').validate(nil, 'setup')"), vim.NIL)
  eq(warnings(), {})
end

T["validate() rejects a non-table"] = function()
  eq(validate("x"), vim.NIL)
  eq(warnings(), { "converge: setup: overrides must be a table" })
end

T["validate() ignores unknown keys"] = function()
  local clean = validate({ from = { beta = { "Comment" } }, colors = {} })
  eq(clean.from, { beta = { "Comment" } })
  eq(vim.tbl_isempty(clean.set), true)
  eq(warnings(), { "converge: setup: unknown overrides key 'colors' ignored" })
end

T["validate() skips bad from entries"] = function()
  local clean = validate({
    from = { beta = "Comment", gamma = { "Comment", 3, "" }, converge = { "Comment" } },
  })
  eq(clean.from, { gamma = { "Comment" } })
  eq(warnings(), {
    "converge: setup: overrides.from.beta must be a list of group names",
    "converge: setup: overrides.from cannot use 'converge'",
    "converge: setup: overrides.from.gamma has an invalid group name, ignored",
  })
end

T["validate() skips bad set entries"] = function()
  local clean = validate({ set = { Visual = "#ffffff", Comment = { fg = "#ffffff" } } })
  eq(clean.set, { Comment = { fg = "#ffffff" } })
  eq(warnings(), { "converge: setup: overrides.set.Visual must be a table, ignored" })
end

T["validate() needs from and set to be tables"] = function()
  eq(validate({ from = "x", set = 3 }), vim.NIL)
  eq(warnings(), {
    "converge: setup: overrides.from must be a table",
    "converge: setup: overrides.set must be a table",
  })
end

T["themes() and counts()"] = function()
  local got = child.lua_get([[(function()
    local o = require("converge.overrides")
    local ov = o.validate({
      from = { nord = { "Comment", "@comment" }, gruvbox = { "String" } },
      set = { Visual = { bg = "#000000" } },
    }, "setup")
    local f, s = o.counts(ov)
    local f0, s0 = o.counts(nil)
    return { themes = o.themes(ov), none = o.themes(nil), counts = { f, s, f0, s0 } }
  end)()]])
  eq(got.themes, { "gruvbox", "nord" })
  eq(got.none, {})
  eq(got.counts, { 3, 1, 0, 0 })
end

return T
