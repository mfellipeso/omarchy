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

-- Push-to-talk for Discord on Right Control (xkb code:105). Needs Discord under
-- XWayland as well: see setup/setup-discord.sh.
--
-- Hyprland matches the modmask from before the key, and Right Control is itself
-- a modifier, so the press arrives without CTRL and the release with it -- two
-- binds. Cover the other modifiers too, or releasing while holding SHIFT never
-- sends the up and latches the mic open. hl.dsp.pass is meant to handle all of
-- this alone, but leaks the release.
--
-- Inject by keycode, not by the name "Control_R": a name is resolved against the
-- active keyboard's keymap, and fcitx5's virtual keyboard keeps taking the seat,
-- so that lookup intermittently fails with "key not found".
local function ptt(state)
  return function()
    hl.dispatch(hl.dsp.send_key_state({
      mods = "", key = "code:105", state = state, window = "class:^(discord)$",
    }))
  end
end

for _, mods in ipairs({
  "", "SHIFT", "ALT", "SUPER",
  "SHIFT + ALT", "SHIFT + SUPER", "ALT + SUPER", "SHIFT + ALT + SUPER",
}) do
  local held = mods == "" and "" or mods .. " + "

  -- Described once, so the keybindings menu shows one row instead of sixteen.
  o.bind(held .. "code:105", mods == "" and "Discord push-to-talk" or nil, ptt("down"))
  o.bind(held .. "CTRL + code:105", nil, ptt("up"), { release = true })
end

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

-- Was: Universal paste. Clipboard manager also stays on SUPER + CTRL + V.
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
