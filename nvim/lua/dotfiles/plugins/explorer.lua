-- Quem liga o explorer do snacks é o extra editor.snacks_explorer, trocado pelo
-- editor.neo-tree do Omarchy no setup-nvim.sh. Aqui só ajustamos o layout e
-- fazemos o <leader>e abrir na raiz do git em vez da raiz do LSP/cwd.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            layout = {
              preset = "sidebar",
              preview = false,
              hidden = { "input" },
            },
          },
        },
      },
    },
    keys = {
      {
        "<leader>e",
        function()
          Snacks.explorer({ cwd = LazyVim.root.git() })
        end,
        desc = "Explorer (project root)",
      },
    },
  },
}
