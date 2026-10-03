-- Like kanagawa: only clears when a scheme is loaded, and leaves @string on its default
-- link to String.
if vim.g.colors_name then
  vim.cmd("hi clear")
end
vim.g.colors_name = "noclear"
vim.api.nvim_set_hl(0, "Normal", { fg = 0x700001, bg = 0x700002 })
vim.api.nvim_set_hl(0, "String", { fg = 0x700004 })
