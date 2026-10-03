---Load a theme and read everything it set.
local cache = require("converge.cache")

local M = {}

---The file `:colorscheme name` loads: like Neovim, `.vim` before `.lua`, and for each the
---runtime path before packages (opt packages are found too).
---@param name string
---@return string|nil path
local function source_path(name)
  for _, ext in ipairs({ "vim", "lua" }) do
    local rel = "colors/" .. name .. "." .. ext
    local path = vim.api.nvim_get_runtime_file(rel, false)[1]
      or vim.fn.globpath(vim.o.packpath, "pack/*/{start,opt}/*/" .. rel, false, true)[1]
    if path then
      return path
    end
  end
  return nil
end

local function source_of(name)
  local path = source_path(name)
  return path and { path = path, mtime = cache.stamp(path) } or nil
end

---Must not run inside a colorscheme script: Neovim ignores a nested `:colorscheme`.
---@param name string
---@param background string 'background' to load the theme with
---@return table|nil snapshot
---@return string|nil err
function M.capture(name, background)
  -- Start from Neovim's defaults: many themes only run `:hi clear` when g:colors_name is
  -- set, and would otherwise keep groups from the current mix. `:hi clear` also unsets
  -- g:colors_name, so setting 'background' below does not reload any scheme.
  vim.cmd("hi clear")
  vim.o.background = background

  local ok, err = pcall(vim.cmd.colorscheme, name)
  if not ok then
    return nil, tostring(err)
  end

  -- nvim_get_hl(0, {}) keeps links; resolve each group so a slice keeps its source look
  -- even when a link points into another slice.
  local groups = {}
  for group in pairs(vim.api.nvim_get_hl(0, {})) do
    local attrs = vim.api.nvim_get_hl(0, { name = group, link = false })
    attrs.default = nil
    -- nvim_get_hl omits an empty cterm. Replaying a group without it makes Neovim derive
    -- cterm from the gui attributes, which the source theme never had.
    attrs.cterm = attrs.cterm or {}
    groups[group] = attrs
  end

  local terminal = {}
  for i = 0, 15 do
    terminal[tostring(i)] = vim.g["terminal_color_" .. i]
  end

  return {
    version = cache.VERSION,
    name = name,
    background = vim.o.background,
    source = source_of(name),
    groups = groups,
    terminal = terminal,
  },
    nil
end

return M
