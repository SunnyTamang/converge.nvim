# converge.nvim

Mix parts of installed color schemes into one. Syntax from one theme, editor UI from
another, terminal colors from a third. Pick with a live preview.

Requires Neovim 0.10 or newer. No dependencies.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "sunnytamang/converge.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("converge").setup({
      recipe = { ui = "tokyonight-night", syntax = "catppuccin-mocha" },
    })
    vim.cmd.colorscheme("converge")
  end,
},
```

Themes in the recipe work even when lazy.nvim loads them lazily: converge loads them with
`:colorscheme`, which lets lazy.nvim load the theme's plugin first. The picker also lists
lazy themes that are not loaded yet.

## Setup

```lua
require("converge").setup({
  recipe = {
    ui = "tokyonight-night",
    syntax = "catppuccin-mocha",
    terminal = "gruvbox",
  },
})
vim.cmd.colorscheme("converge")
```

Slices: `ui`, `syntax`, `diagnostics`, `git`, `terminal`, `plugins`.
A slice you leave out uses the `ui` theme.

## Picker

`:Converge` opens the picker.

| Key | Slice list | Theme list |
|---|---|---|
| `<CR>` | pick a theme for this slice | keep this theme |
| `<Esc>` | close (undo unsaved) | undo, back to slices |
| `s` | save the recipe | |
| `y` | copy the recipe as Lua | |
| `q` | close (undo unsaved) | close (undo unsaved) |

A saved recipe wins over the one in `setup()`.

## Commands

- `:Converge reset` - delete the saved recipe.
- `:Converge refresh` - delete the cache and read all themes again.

## How it works

Each theme is loaded once. Its colors are saved in `stdpath("cache")/converge/`.
The cache refreshes when the theme's files change (everything in the theme's `colors/` and
`lua/` folders). The first time a theme is used (a cold cache), `ColorScheme` fires once for
each theme that is read, and the old colors stay for one moment while that happens.

Theme options (for example a `setup()` call of the theme) are not part of its files. After
changing a theme's options, run `:Converge refresh`.
