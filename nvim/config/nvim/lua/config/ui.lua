local hidden_filetypes = {
  aerial = true,
  ["neo-tree"] = true,
  ["neo-tree-popup"] = true,
  Trouble = true,
  help = true,
  lazy = true,
  mason = true,
  oil = true,
  qf = true,
  trouble = true,
  toggleterm = true,
}

function _G.user_winbar()
  if vim.bo.buftype == "terminal" or hidden_filetypes[vim.bo.filetype] then
    return ""
  end

  local name = vim.fn.expand("%:t")
  if name == "" then
    name = "[No Name]"
  end

  local modified = vim.bo.modified and " +" or ""
  local navic = package.loaded["nvim-navic"]

  if navic and navic.is_available() then
    local location = navic.get_location()

    if location ~= "" then
      return " " .. name .. modified .. " > " .. location
    end
  end

  return " " .. name .. modified
end
