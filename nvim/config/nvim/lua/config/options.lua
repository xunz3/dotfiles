local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.numberwidth = 4
opt.cursorline = true
opt.cursorlineopt = "number,line"
opt.signcolumn = "yes"
opt.termguicolors = true
opt.showmode = false
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.showtabline = 2
opt.winbar = "%{%v:lua.user_winbar()%}"

opt.splitright = true
opt.splitbelow = true
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
opt.wrap = false
opt.linebreak = true
opt.breakindent = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wildmode = { "longest", "full" }
opt.inccommand = "split"
opt.splitkeep = "screen"

opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true

opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.timeoutlen = 300
opt.updatetime = 250
opt.completeopt = { "menu", "menuone", "noselect" }
opt.pumheight = 10
opt.confirm = true
opt.hidden = true
opt.laststatus = 3
opt.fillchars = { eob = " " }

opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true

opt.shortmess:append("c")
opt.iskeyword:append("-")

local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
if vim.fn.isdirectory(mason_bin) == 1 then
  vim.env.PATH = mason_bin .. ":" .. vim.env.PATH
end
