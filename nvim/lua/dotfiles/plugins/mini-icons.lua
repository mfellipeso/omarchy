return {
  {
    "nvim-mini/mini.icons",
    opts = {
      extension = {
        -- Test icons
        ["spec.ts"] = { glyph = "󰙨", hl = "MiniIconsOrange" },
        ["spec.tsx"] = { glyph = "󰜈", hl = "MiniIconsOrange" },
        ["e2e-spec.ts"] = { glyph = "󰙨", hl = "MiniIconsOrange" },
        ["gateway-spec.ts"] = { glyph = "󰙨", hl = "MiniIconsOrange" },

        -- Nest js
        ["module.ts"] = { glyph = "", hl = "MiniIconsRed" },
        ["service.ts"] = { glyph = "", hl = "MiniIconsYellow" },
        ["controller.ts"] = { glyph = "", hl = "MiniIconsBlue" },
        ["guard.ts"] = { glyph = "", hl = "MiniIconsGreen" },
      },
    },
  },
}
