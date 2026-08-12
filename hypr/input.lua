-- Personal input overrides. Omarchy's defaults load first, so the settings
-- below replace them.

hl.config({
  input = {
    -- ThinkPad ABNT2 keyboard. Omarchy normally takes this from XKBLAYOUT in
    -- /etc/vconsole.conf, but setting it here keeps it with the dotfiles
    -- instead of per machine. External keyboards override it further down.
    kb_layout = "br",
    kb_variant = "thinkpad",

    -- No compose key. Omarchy's default is "compose:caps,shift:both_capslock_cancel",
    -- which puts compose on CapsLock and moves CapsLock itself onto both
    -- Shifts. Clearing this restores a plain CapsLock key.
    kb_options = "",

    -- Turn off mouse acceleration (default: adaptive).
    accel_profile = "flat",

    -- Sensitivity is left at Omarchy's default of 0; raise it here if the
    -- pointer feels slow (the old ThinkPad config used 0.45).
    -- sensitivity = 0.45,

    -- Cursor focus detached from keyboard focus: clicking a window is what
    -- moves keyboard focus to it.
    follow_mouse = 2,

    touchpad = {
      -- Use natural (inverse) scrolling.
      natural_scroll = true,
    },
  },

  cursor = {
    -- Don't auto-center the cursor when window focus changes.
    no_warps = true,
  },
})

-- Logitech M720 Triathlon. The hardware DPI is fixed, so a per-device
-- sensitivity boost is how the pointer gets faster; scoped here so the
-- touchpad/trackpoint keep the default speed. The node name gains a "-1"
-- suffix depending on how it reconnects, so both spellings get the setting.
hl.device({ name = "logitech-m720-triathlon-multi-device-mouse", sensitivity = 1 })
hl.device({ name = "logitech-m720-triathlon-multi-device-mouse-1", sensitivity = 1 })

-- Aula F75, which enumerates under its ODM name. The keyboard exposes several
-- input nodes and the typing one is not stable between the two, so both get
-- the layout.
hl.device({ name = "by-tech-gaming-keyboard", kb_layout = "us", kb_variant = "intl" })
hl.device({ name = "by-tech-gaming-keyboard-1", kb_layout = "us", kb_variant = "intl" })
