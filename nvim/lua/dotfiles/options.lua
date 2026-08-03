vim.opt.fixendofline = true

vim.api.nvim_create_user_command("CopyAbsPath", function()
  vim.fn.setreg("+", vim.fn.expand("%:p"))
  vim.notify("Copied absolute path to clipboard!")
end, {})

vim.api.nvim_create_user_command("CopyRelPath", function()
  local rel_path = vim.fn.fnamemodify(vim.fn.expand("%"), ":.")
  vim.fn.setreg("+", rel_path)
  vim.notify('Copied relative path "' .. rel_path .. '" to clipboard!')
end, {})
