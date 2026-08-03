-- Entry point for the personal Hyprland config.
--
-- ~/.config/hypr/hyprland.lua loads this with a single line:
--   dofile(os.getenv("HOME") .. "/.dotfiles/hypr/init.lua")
--
-- Everything else lives in this repo, so Omarchy's own files under
-- ~/.config/hypr stay stock and keep receiving upstream updates. Nothing here
-- is symlinked into ~/.config, which also keeps it clear of the `sed -i` calls
-- Omarchy's tooling makes on files it owns.
--
-- Loaded after Omarchy's defaults and after its user-file requires, so these
-- assignments win. Order below matters only to us: bindings unbind Omarchy
-- defaults before rebinding them.

local dir = os.getenv("HOME") .. "/.dotfiles/hypr/"

dofile(dir .. "input.lua")
dofile(dir .. "bindings.lua")
dofile(dir .. "windows.lua")
