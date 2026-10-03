---Preview buffer for the picker. Shows every slice, also slices not on screen.
local M = {}

local ns = vim.api.nvim_create_namespace("converge.preview")

---Window-local groups for terminal swatches. Kept out of the global namespace so they
---never end up in a captured snapshot.
M.hl_ns = vim.api.nvim_create_namespace("converge.preview.hl")

local CODE = {
  "local function greet(name)",
  "  local count = 42",
  '  return "hello " .. name',
  "end",
}

-- { text, highlight group }
local MARKS = {
  { "E undefined global 'x'", "DiagnosticError" },
  { "W unused local 'y'", "DiagnosticWarn" },
  { "+ added line", "Added" },
  { "~ changed line", "Changed" },
  { "- removed line", "Removed" },
}

local SWATCH = "  "

local function highlight_code(buf)
  local text = table.concat(CODE, "\n")
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "lua")
  local query = ok and vim.treesitter.query.get("lua", "highlights")
  if not query then
    return
  end
  for id, node in query:iter_captures(parser:parse()[1]:root(), text) do
    local capture = query.captures[id]
    if not vim.startswith(capture, "_") then
      local sr, sc, er, ec = node:range()
      vim.api.nvim_buf_set_extmark(buf, ns, sr, sc, {
        end_row = er,
        end_col = ec,
        hl_group = "@" .. capture .. ".lua",
      })
    end
  end
end

---@return integer buf
function M.create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local lines = vim.list_extend({}, CODE)
  table.insert(lines, "")
  local first_mark = #lines -- 0-based row of the first mark line
  for _, mark in ipairs(MARKS) do
    table.insert(lines, mark[1])
  end
  table.insert(lines, "")
  table.insert(lines, string.rep(SWATCH, 16))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  highlight_code(buf)
  for i, mark in ipairs(MARKS) do
    vim.api.nvim_buf_set_extmark(buf, ns, first_mark + i - 1, 0, {
      end_col = #mark[1],
      hl_group = mark[2],
    })
  end
  for i = 0, 15 do
    vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, i * #SWATCH, {
      end_col = (i + 1) * #SWATCH,
      hl_group = "ConvergeTerm" .. i,
    })
  end
  return buf
end

---Update the terminal swatches from the current terminal colors.
function M.refresh()
  for i = 0, 15 do
    local color = vim.g["terminal_color_" .. i]
    vim.api.nvim_set_hl(M.hl_ns, "ConvergeTerm" .. i, color and { bg = color } or {})
  end
end

---@param win integer
function M.attach(win)
  -- Groups missing from M.hl_ns fall back to the global ones.
  vim.api.nvim_win_set_hl_ns(win, M.hl_ns)
  M.refresh()
end

return M
