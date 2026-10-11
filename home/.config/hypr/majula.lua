-- Majula: theme and session extras.
-- Loaded by the last line of hyprland.lua; comment out require("majula") to turn it all off.

local c = {
    background = "0E1114",
    surface    = "171C20",
    border     = "465056",
    accent     = "D1A35C",
    ember      = "E0783E",
}

local function rgba(hex, alpha)
    return "rgba(" .. hex .. (alpha or "ff") .. ")"
end

local mainMod = "SUPER"
local scripts = "~/.config/hypr/scripts/"

-------------------
------ LOOK -------
-------------------

hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { rgba(c.ember), rgba(c.accent) }, angle = 45 },
            inactive_border = rgba(c.border, "99"),
        },
        resize_on_border = true,
    },

    decoration = {
        rounding = 8,

        shadow = {
            enabled        = true,
            range          = 14,
            render_power   = 3,
            color          = rgba("000000", "88"),
            color_inactive = rgba("000000", "44"),
        },

        blur = {
            enabled  = true,
            size     = 6,
            passes   = 2,
            vibrancy = 0.15,
            noise    = 0.02,
            popups   = true,
        },
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = rgba(c.background),
    },
})

-- Num Lock always on, and the keypad covers the broken 5 and 6 keys:
-- Shift + keypad 1..0 types ! @ # $ % ¨ & * ( ). See ~/.config/xkb/symbols/majula.
-- Touchpad scrolling at half speed (raise scroll_factor if it feels too slow).
hl.config({
    input = {
        kb_layout  = "br",
        kb_options = "majula:keypad",
        numlock_by_default = true,
        touchpad = {
            scroll_factor = 0.5,
        },
    },
})

-- Blur behind the bar, the launcher and notifications.
hl.layer_rule({
    name  = "majula-blur",
    match = { namespace = "^(waybar|rofi|notifications)$" },
    blur  = true,
    ignore_alpha = 0.2,
})

hl.window_rule({
    name   = "majula-float-tools",
    match  = { class = "^(org.pulseaudio.pavucontrol|nm-connection-editor|qt6ct)$" },
    float  = true,
    size   = "760 480",
    center = true,
})

-------------------
---- AUTOSTART ----
-------------------

-- nm-applet and dunst start on their own (XDG autostart / D-Bus).
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- waybar")
    hl.exec_cmd("uwsm app -- hyprpaper")
    hl.exec_cmd("uwsm app -- hypridle")
    hl.exec_cmd("uwsm app -- wl-paste --watch cliphist store")
    hl.exec_cmd("uwsm app -- /usr/lib/polkit-kde-authentication-agent-1")
end)

------------------
---- KEYBINDS ----
------------------

-- Super+R opens the app launcher (it used to be rofi -show run).
hl.unbind(mainMod .. " + R")
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("rofi -show drun"))

hl.bind(mainMod .. " + B",          hl.dsp.exec_cmd("zen-browser"))
hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + ESCAPE",     hl.dsp.exec_cmd(scripts .. "power-menu"))
hl.bind(mainMod .. " + SHIFT + V",  hl.dsp.exec_cmd(scripts .. "clipboard"))
hl.bind("PRINT",                    hl.dsp.exec_cmd(scripts .. "screenshot area"))
hl.bind("SHIFT + PRINT",            hl.dsp.exec_cmd(scripts .. "screenshot full"))
hl.bind(mainMod .. " + SHIFT + R",  hl.dsp.exec_cmd(scripts .. "rice"))   -- rice showcase (again = close)

-- Broken F2 and F5: AltGr + the key to their left sends them to the active window.
hl.bind("MOD5 + F1", hl.dsp.send_shortcut({ mods = "", key = "F2" }))
hl.bind("MOD5 + F4", hl.dsp.send_shortcut({ mods = "", key = "F5" }))

-- Super + keypad 1..9 and 0 (= 10) switch workspaces; with Shift, the window goes along.
-- Uses the physical key codes, so it works with Num Lock on or off.
local keypad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }

for workspace, code in ipairs(keypad) do
    hl.bind(mainMod .. " + code:" .. code,             hl.dsp.focus({ workspace = workspace }))
    hl.bind(mainMod .. " + SHIFT + code:" .. code,     hl.dsp.window.move({ workspace = workspace }))
end
