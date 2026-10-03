if vim.g.loaded_converge then
  return
end
vim.g.loaded_converge = true

vim.api.nvim_create_user_command("Converge", function(cmd)
  require("converge").command(cmd.fargs[1])
end, {
  nargs = "?",
  complete = function()
    return { "refresh", "reset" }
  end,
  desc = "Mix parts of color schemes",
})
