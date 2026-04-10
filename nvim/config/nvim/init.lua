if vim.loader then
  vim.loader.enable()
end

-- nvim-tree recommends disabling netrw before plugin setup.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.ui")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
