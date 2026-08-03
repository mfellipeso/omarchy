-- O Omarchy liga o extra editor.neo-tree no lazyvim.json dele, e o neo-tree
-- também reivindica <leader>e. Como a preferência aqui é o explorer do snacks,
-- ele é desligado daqui em vez de mexer no lazyvim.json — apagar este arquivo
-- devolve o padrão do Omarchy.
return {
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

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
