-- Personal look'n'feel overrides. Loaded from hyprland.lua, after Omarchy's defaults.

-- Smaller outer gaps (Omarchy default is 10).
hl.config({
    general = {
        gaps_out = 5,
    },
})

-- Allow games marked "immediate" (see windows.lua) to tear. Only takes effect
-- while the game is fullscreen and alone on screen.
hl.config({
    general = {
        allow_tearing = true,
    },
})
