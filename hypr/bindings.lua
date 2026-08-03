-- Personal keybindings. Omarchy's defaults load first, so anything here adds
-- to them or overrides them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- Additions -- these keys are unbound in Omarchy's defaults.

-- Replaces the old waybar mic-toggle.sh; drives the mic-mute LED too.
o.bind("CTRL + ESCAPE", "Toggle microphone", "omarchy-audio-input-mute")

-- Omarchy also binds this to SUPER + J.
o.bind("SUPER + H", "Toggle window split", hl.dsp.layout("togglesplit"))

-- Omarchy also binds this to SUPER + CTRL + DELETE.
o.bind("SUPER + SHIFT + L", "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle")

-- Overrides -- each unbinds an Omarchy default before rebinding the key.

-- Was: Close window. Moved to SUPER + Q.
hl.unbind("SUPER + W")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- Was: Toggle workspace layout. Lock also stays on SUPER + CTRL + L.
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock screen", "omarchy-system-lock")

-- Was: Toggle scratchpad. Screenshot also stays on PRINT.
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Screenshot", "omarchy-capture-screenshot")

-- Omarchy also binds the capture menu to SUPER + CTRL + C.
o.bind("SUPER + SHIFT + S", "Capture menu", "omarchy-menu toggle capture")
