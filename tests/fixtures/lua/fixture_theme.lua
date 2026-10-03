-- Predictable test themes. Every color is `tag * 0x10000 + n`.
local M = {}

---@param name string
---@param tag integer
---@param background string|nil force 'background'; nil keeps the current value
function M.define(name, tag, background)
  vim.cmd("hi clear")
  if background then
    vim.o.background = background
  end
  vim.g.colors_name = name
  vim.g.fixture_loads = (vim.g.fixture_loads or 0) + 1

  local function c(n)
    return tag * 0x10000 + n
  end
  local function hl(group, attrs)
    vim.api.nvim_set_hl(0, group, attrs)
  end

  hl("Normal", { fg = c(1), bg = c(2) })
  -- cterm = {} stops Neovim from deriving a cterm copy of `italic`, keeping snapshots exact.
  hl("Comment", { fg = c(3), italic = true, cterm = {} })
  hl("String", { fg = c(4) })
  hl("@string", { link = "String" })
  hl("Function", { fg = c(5) })
  hl("DiagnosticError", { fg = c(6) })
  hl("DiffAdd", { bg = c(7) })
  hl("Added", { fg = c(8) })
  hl("TelescopeNormal", { fg = c(9) })
  hl("StatusLine", { fg = c(10), bg = c(11) })
  hl("CursorLineNr", { link = "Comment" }) -- a ui group linking into the syntax slice

  for i = 0, 15 do
    vim.g["terminal_color_" .. i] = string.format("#%02x00%02x", tag, i)
  end
end

return M
