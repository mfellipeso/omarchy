-- Shipping this file replaces the hyprland.lua Omarchy renders from colors.toml,
-- so the border colors are spelled out here: same as stock Catppuccin.
local active_border_color = "#89b4fa"
local inactive_border_color = "rgba(595959aa)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  -- Barely rounded. The omarchy-shell mirrors this value on its own panels.
  -- decoration = {
  --   rounding = 3,
  -- },
})
