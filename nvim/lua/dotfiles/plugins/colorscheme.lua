-- Fallback de tema, só para quando o Omarchy não estiver no comando.
--
-- Quem manda no tema é o Omarchy: ele symlinka lua/plugins/theme.lua para o
-- tema atual e faz hot-reload no `omarchy theme set`. Enquanto esse symlink
-- resolver, este arquivo não devolve nada e não briga por opts.colorscheme.
--
-- Sem ele — máquina sem Omarchy, ou symlink quebrado — o LazyVim cairia no
-- default dele, tokyonight. Aqui o fallback é o mesmo ashen que o tema Solitude
-- usa. fs_stat segue o symlink, então um link pendurado também cai para cá.
local theme = vim.fn.stdpath("config") .. "/lua/plugins/theme.lua"
if (vim.uv or vim.loop).fs_stat(theme) then
  return {}
end

return {
  { "ficcdaf/ashen.nvim" },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "ashen",
    },
  },
}
