local H = dofile("tests/helpers.lua")
local eq = MiniTest.expect.equality

local child = MiniTest.new_child_neovim()

-- Every tag the help file must define.
local TAGS = {
  "converge",
  "converge.nvim",
  "converge-contents",
  "converge-setup",
  "converge-recipe",
  "converge-slices",
  "converge-overrides",
  "converge-groups",
  "converge-picker",
  "converge-commands",
  ":Converge",
  ":Converge-reset",
  ":Converge-refresh",
  "converge-health",
  "converge-files",
}

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      H.start(child)
      -- Build the tags in a copy, so the repo gets no generated doc/tags file.
      child.lua([[
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir .. "/doc", "p")
        vim.fn.writefile(vim.fn.readfile("doc/converge.txt"), dir .. "/doc/converge.txt")
        vim.cmd("helptags " .. dir .. "/doc")
        vim.opt.rtp:prepend(dir)
      ]])
    end,
    post_once = child.stop,
  },
})

T["helptags builds without errors"] = function()
  -- :helptags errors on duplicate tags; pre_case would have failed.
  eq(child.lua_get("vim.v.errmsg"), "")
end

T["every tag opens the help file"] = function()
  for _, tag in ipairs(TAGS) do
    child.cmd("help " .. tag)
    local name = child.lua_get("vim.fs.basename(vim.api.nvim_buf_get_name(0))")
    local line = child.lua_get("vim.api.nvim_get_current_line()")
    eq({ tag = tag, file = name }, { tag = tag, file = "converge.txt" })
    eq(
      { tag = tag, found = line:find("*" .. tag .. "*", 1, true) ~= nil },
      { tag = tag, found = true }
    )
    child.cmd("helpclose")
  end
end

T["lines fit in 78 columns"] = function()
  local long = child.lua_get([[(function()
    local out = {}
    for i, l in ipairs(vim.fn.readfile("doc/converge.txt")) do
      if vim.fn.strdisplaywidth(l) > 78 then
        table.insert(out, i)
      end
    end
    return out
  end)()]])
  eq(long, {})
end

return T
