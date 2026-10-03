-- Test init: the repo on 'runtimepath', and mini.test when running headless.
vim.opt.rtp:append(vim.fn.getcwd())

if #vim.api.nvim_list_uis() == 0 then
  vim.opt.rtp:append(vim.fn.getcwd() .. "/deps/mini.nvim")
  require("mini.test").setup()
end
