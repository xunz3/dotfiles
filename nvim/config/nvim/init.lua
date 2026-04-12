if vim.loader then
  vim.loader.enable()
end

-- External file explorers handle directory buffers; keep netrw out of the way.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.ui")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
