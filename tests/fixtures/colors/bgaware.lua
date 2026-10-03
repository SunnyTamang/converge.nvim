-- Different colors for dark and light, like gruvbox.
require("fixture_theme").define("bgaware", vim.o.background == "light" and 0x50 or 0x40)
