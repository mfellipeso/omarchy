-- Personal window rules. Loaded from hyprland.lua, after Omarchy's defaults.

-- HoYoPlay's launcher tiles itself into whatever it lands on; float it instead.
o.window({ title = "^HoYoPlay$" }, { float = true, center = true })

-- Taskbar Hero (Steam app 3678970) sits behind the taskbar as pure decoration;
-- strip all chrome and keep it from stealing focus.
o.window({ class = "^steam_app_3678970$" }, {
    name = "taskbar-hero-decor",
    match = { class = "steam_app_3678970" },
    border_size = 0,
    rounding = 0,
    border_color = { colors = { "rgba(00000000)", "rgba(00000000)" } },
    no_shadow = true,
    decorate = false,
    float = true,
    no_initial_focus = true,
    focus_on_activate = false,
})
