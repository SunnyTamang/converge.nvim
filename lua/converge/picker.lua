---Floating picker: choose a theme per slice, with live preview.
local config = require("converge.config")
local log = require("converge.log")
local overrides = require("converge.overrides")
local preview = require("converge.preview")
local slices = require("converge.slices")
local store = require("converge.store")
local themes = require("converge.themes")

local M = {}

local LEFT_WIDTH, RIGHT_WIDTH, HEIGHT = 36, 40, 13

---@type table|nil
local state = nil

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Title on the top border, key hints on the bottom border.
local function set_frame(title, keys)
  vim.api.nvim_win_set_config(state.win, {
    title = " " .. title .. " ",
    title_pos = "left",
    footer = " " .. keys .. " ",
    footer_pos = "left",
  })
end

local function show()
  require("converge").preview(state.recipe, state.background)
  preview.refresh()
end

local function show_slices()
  state.mode = "slices"
  local lines, row = {}, 1
  for i, name in ipairs(slices.names) do
    table.insert(lines, string.format(" %-12s %s", name, state.recipe[name]))
    if name == state.slice then
      row = i
    end
  end
  -- Overrides are edited in the config only; show them as one read-only line.
  local from_n, set_n = overrides.counts(state.recipe.overrides)
  if from_n + set_n > 0 then
    table.insert(lines, string.format(" %-12s %d from, %d set", "overrides", from_n, set_n))
  end
  set_lines(state.buf, lines)
  set_frame("Slices", "s save  q quit")
  vim.api.nvim_win_set_cursor(state.win, { row, 0 })
end

local function show_themes(slice)
  state.mode = "themes"
  state.slice = slice
  state.before = state.recipe[slice]
  state.themes = themes.list()
  set_lines(state.buf, state.themes)
  set_frame(slice .. ": pick a theme", "Enter keep  Esc back")
  local row = 1
  for i, name in ipairs(state.themes) do
    if name == state.before then
      row = i
    end
  end
  state.row = row
  vim.api.nvim_win_set_cursor(state.win, { row, 0 })
end

local function on_cursor_moved()
  if not state or state.mode ~= "themes" then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  -- Only react to real moves, not to the initial cursor placement.
  if row == state.row then
    return
  end
  state.row = row
  local theme = state.themes[row]
  if theme and theme ~= state.recipe[state.slice] then
    local previous = state.recipe[state.slice]
    state.recipe[state.slice] = theme
    local ok, err = pcall(show)
    if not ok then
      state.recipe[state.slice] = previous
      log.warn("preview failed: " .. tostring(err))
    end
  end
end

local function on_enter()
  if state.mode == "slices" then
    local slice = slices.names[vim.api.nvim_win_get_cursor(state.win)[1]]
    if slice then -- nil on the read-only overrides line
      show_themes(slice)
    end
  else
    show_slices() -- keep the current choice
  end
end

local function on_escape()
  if state.mode == "slices" then
    return M.close()
  end
  if state.recipe[state.slice] ~= state.before then
    state.recipe[state.slice] = state.before
    show()
  end
  show_slices()
end

local function on_save()
  if state.mode ~= "slices" then
    return
  end
  local ok, err = pcall(store.write, config.slices_of(state.recipe))
  if not ok then
    return log.warn("could not save the recipe: " .. tostring(err))
  end
  state.saved = true
  vim.notify("converge: recipe saved", vim.log.levels.INFO)
end

local function on_copy()
  if state.mode ~= "slices" then
    return
  end
  local text = config.to_lua(state.recipe)
  vim.fn.setreg('"', text)
  pcall(vim.fn.setreg, "+", text) -- no clipboard provider is fine
  vim.notify("converge: recipe copied", vim.log.levels.INFO)
end

---Build the picker windows and keymaps. Returns the new state; module state is untouched.
local function build()
  local s = {
    recipe = config.resolve(),
    previous = vim.g.colors_name,
    -- Previews of themes that force 'background' change it; undo needs the old value.
    background = vim.o.background,
    saved = false,
  }
  local ok, err = pcall(function()
    local width = LEFT_WIDTH + RIGHT_WIDTH + 4
    local row = math.max(0, math.floor((vim.o.lines - HEIGHT) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))
    local base = {
      relative = "editor",
      row = row,
      height = HEIGHT,
      border = "rounded",
      style = "minimal",
      title_pos = "left",
    }

    s.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[s.buf].bufhidden = "wipe"
    s.win = vim.api.nvim_open_win(
      s.buf,
      true,
      vim.tbl_extend("force", base, { col = col, width = LEFT_WIDTH, title = " Slices " })
    )
    vim.wo[s.win].cursorline = true

    s.preview_buf = preview.create_buf()
    s.preview_win = vim.api.nvim_open_win(
      s.preview_buf,
      false,
      vim.tbl_extend("force", base, {
        col = col + LEFT_WIDTH + 2,
        width = RIGHT_WIDTH,
        title = " Preview ",
        focusable = false,
      })
    )
    preview.attach(s.preview_win)
    -- Stop other buffers from opening in the picker windows (Neovim 0.10.1+).
    if vim.fn.exists("+winfixbuf") == 1 then
      vim.wo[s.win].winfixbuf = true
      vim.wo[s.preview_win].winfixbuf = true
    end
  end)
  if not ok then
    for _, win in ipairs({ s.win, s.preview_win }) do
      if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs({ s.buf, s.preview_buf }) do
      if buf and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    return nil, err
  end
  return s
end

function M.open()
  if state then
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
      return
    end
    M.close() -- stale state, start fresh
  end
  local s, err = build()
  if not s then
    log.warn("cannot open picker: " .. tostring(err))
    return
  end
  state = s

  local ok, setup_err = pcall(function()
    local function map(lhs, fn)
      vim.keymap.set("n", lhs, fn, { buffer = s.buf, nowait = true })
    end
    map("<CR>", on_enter)
    map("<Esc>", on_escape)
    map("q", M.close)
    map("s", on_save)
    map("y", on_copy)

    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = s.buf,
      -- Previews load themes. Without `nested`, their ColorSchemePre / ColorScheme events do
      -- not fire, and lazy.nvim loads a lazy theme on ColorSchemePre.
      nested = true,
      callback = on_cursor_moved,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(s.win),
      once = true,
      -- Window layout changes are not allowed inside WinClosed. By the next tick another
      -- picker may be open, so only close the one this autocmd belongs to.
      callback = vim.schedule_wrap(function()
        if state == s then
          M.close()
        end
      end),
    })

    show_slices()
    show()
  end)
  if not ok then
    M.close()
    log.warn("cannot open picker: " .. tostring(setup_err))
  end
end

---Close the picker. Unsaved changes are undone.
function M.close()
  if not state then
    return
  end
  local s = state
  state = nil
  for _, win in ipairs({ s.win, s.preview_win }) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  -- Put 'background' back without reloading the scheme a preview left behind.
  vim.g.colors_name = nil
  vim.o.background = s.background
  if s.saved or s.previous == "converge" then
    vim.cmd.colorscheme("converge")
  else
    pcall(vim.cmd.colorscheme, s.previous or "default")
  end
end

return M
