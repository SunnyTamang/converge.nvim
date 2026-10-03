-- Shared helpers for tests that drive a child Neovim.
local H = {}

---Start (or restart) a child Neovim with isolated XDG dirs and the fixture themes on 'rtp'.
---Pass the same `root` again to keep cache and data across a restart.
---@param child table MiniTest child
---@param root string|nil
---@return string root
function H.start(child, root)
  root = root or vim.fn.tempname()
  -- The child inherits this process's environment.
  for _, kind in ipairs({ "CACHE", "DATA", "STATE", "CONFIG" }) do
    vim.env["XDG_" .. kind .. "_HOME"] = root .. "/" .. kind:lower()
  end
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.lua([[
    vim.opt.rtp:prepend(vim.fn.getcwd() .. "/tests/fixtures")
    _G.notes = {}
    vim.notify = function(msg, level)
      table.insert(_G.notes, { msg = msg, level = level })
    end
  ]])
  return root
end

---Attributes of `group` in the child, links resolved.
function H.hl(child, group)
  return child.lua_get(string.format("vim.api.nvim_get_hl(0, { name = %q, link = false })", group))
end

---Wait in the child until Lua expression `expr` is true. Errors on timeout.
---@param timeout_ms integer|nil default 5000
function H.wait_for(child, expr, timeout_ms)
  local ok =
    child.lua_get(string.format("vim.wait(%d, function() return %s end)", timeout_ms or 5000, expr))
  if not ok then
    error("timed out waiting for: " .. expr)
  end
end

---Wait until `converge` is the active scheme. A cold cache captures on the next tick.
function H.wait_active(child)
  H.wait_for(child, 'vim.g.colors_name == "converge"')
end

---Let the child's event loop run `n` (default 1) more ticks: callbacks scheduled before
---this call have run when it returns.
function H.ticks(child, n)
  child.lua(
    [[
    _G.ticked = false
    local function tick(left)
      if left == 0 then
        _G.ticked = true
      else
        vim.schedule(function() tick(left - 1) end)
      end
    end
    tick(...)
  ]],
    { n or 1 }
  )
  H.wait_for(child, "_G.ticked")
end

---Color `n` of the fixture theme with tag `tag` (see tests/fixtures/lua/fixture_theme.lua).
function H.color(tag, n)
  return tag * 0x10000 + n
end

---Notifications recorded in the child.
function H.notes(child)
  return child.lua_get("_G.notes")
end

return H
