-- Рабочий конфиг Hyprland (изменение OpenSpec hyprland-config).
-- Источник: ~/.local/share/chezmoi/dot_config/hypr/hyprland.lua, в $HOME
-- попадает через `chezmoi apply`. Запуск: lightdm, запись «Hyprland»
-- (hyprland.desktop → /usr/bin/start-hyprland). Перезагрузка: `hyprctl reload`.
-- Разделы: монитор, окружение, ввод, вид, рабочие столы, правила окон,
-- привязки, автозапуск.

local HOME = os.getenv("HOME")

------------------
---- МОНИТОР ----
------------------

-- DP-2, 3840×2160, родная частота 120 Гц.
hl.monitor({
    output   = "DP-2",
    mode     = "3840x2160@120",
    position = "0x0",
    scale    = 1,
})
-- Запасное правило для любых других выходов.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

--------------------
---- ОКРУЖЕНИЕ ----
--------------------

-- NVIDIA: набор из вики Hyprland, подтверждён проверкой hyprland-nvidia-check.
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- Без этого Firefox на NVIDIA не включает VA-API (вместе с настройками профиля).
hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
-- То, что X11-сессия берёт из ~/.config/openbox/environment и ~/.xprofile.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
-- GTK-приложения и Firefox (режим «auto») выбирают файлы через портал, а портал
-- FileChooser отдан yazi (~/.config/xdg-desktop-portal/hyprland-portals.conf).
hl.env("GTK_USE_PORTAL", "1")
hl.env("LESSHISTFILE", "/dev/null")
-- ~/.local/bin (wezterm, eww) и ~/.bun/bin: неизвестно, применяет ли lightdm
-- login-оболочку к Wayland-сессии, поэтому PATH дополняется здесь.
hl.env("PATH", HOME .. "/.bun/bin:" .. HOME .. "/.local/bin:" .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin"))

---------------
---- ВВОД ----
---------------

-- Карта XKB целиком из файла. Переключение раскладок делает сама карта:
-- Win+Пробел по кругу, Alt+E фиксирует US, Alt+R фиксирует RU.
-- Ни одна привязка ниже не должна занимать эти сочетания.
hl.config({
    input = {
        kb_file      = HOME .. "/.config/X11/xkb_custom",
        follow_mouse = 1,
        sensitivity  = 0,
    },
})

-------------
---- ВИД ----
-------------

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 12,
        border_size = 2,
        col = {
            active_border   = "rgba(7aa2f7ee)",
            inactive_border = "rgba(414868aa)",
        },
        -- Мозаика dwindle доступна через Super+Shift+V; по умолчанию окна
        -- плавающие (правило ниже), как в Openbox.
        layout = "dwindle",
    },
    -- Прозрачность, размытие и тени повторяют правила picom из X11-сессии
    -- (dot_config/picom.conf): окно в фокусе 0.9, без фокуса 0.7, полноэкранное
    -- непрозрачное; скругление 8; тень радиусом 40, плотностью 0.5 со смещением
    -- −27; размытие лёгкое (dual_kawase 1.3) и только у терминалов в фокусе,
    -- см. правила окон ниже.
    decoration = {
        rounding           = 8,
        active_opacity     = 0.9,
        inactive_opacity   = 0.7,
        fullscreen_opacity = 1.0,
        shadow = {
            enabled      = true,
            -- Вчетверо короче тени picom (40) и со смещением вниз и вправо.
            range        = 10,
            render_power = 2,
            offset       = { 7, 7 },
            color        = 0x80000000,
        },
        blur = {
            enabled        = true,
            size           = 3,
            passes         = 1,
            ignore_opacity = true,
            popups         = false,
        },
    },
    animations = {
        enabled = true,
    },
    cursor = {
        -- Аппаратный курсор проверен без артефактов. Переключение на программный
        -- на лету: Super+Shift+C (привязка ниже).
        no_hardware_cursors = false,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    -- Подробный журнал на переходный период: без него в hyprland.log нет окон,
    -- Xwayland и клавиатуры. Файл: $XDG_RUNTIME_DIR/hypr/<сигнатура>/hyprland.log.
    debug = {
        disable_logs = false,
    },
    xwayland = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
})

-- Кривые и анимации из примера Hyprland. В 0.56.2 параметр пружины
-- называется dampening (в примере из main уже damping).
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-----------------------
---- РАБОЧИЕ СТОЛЫ ----
-----------------------

-- Восемь столов «1»…«8» на DP-2, как в Openbox. persistent: стол существует
-- до первого перехода на него.
for i = 1, 8 do
    hl.workspace_rule({
        workspace  = tostring(i),
        monitor    = "DP-2",
        persistent = true,
        default    = (i == 1),
    })
end

----------------------
---- ПРАВИЛА ОКОН ----
----------------------

-- Переходный период до Lua-раскладки зон: все окна открываются плавающими,
-- как в Openbox. Мозаика по Super+Shift+V.
hl.window_rule({
    name  = "float-by-default",
    match = { class = ".*" },
    float = true,
})

-- Прозрачность и размытие как в picom. Правила применяются сверху вниз,
-- нижнее перекрывает верхнее.
-- Размытие ни у кого, кроме терминалов и neovide в фокусе.
hl.window_rule({
    name    = "no-blur-default",
    match   = { class = ".*" },
    no_blur = true,
})
hl.window_rule({
    name    = "blur-terminal-focused",
    match   = { class = "^(org\\.wezfurlong\\.wezterm|termfilechooser|neovide)$", focus = true },
    no_blur = false,
})
-- Браузеры, видео и игры в фокусе непрозрачные; без фокуса общие 0.7.
hl.window_rule({
    name    = "opaque-media-focused",
    match   = {
        class = "(?i)^(firefox|yandex-browser|google-chrome|chromium|mpv|vlc|smplayer|mplayer|gamescope)$|^steam_app_|[.]exe$",
        focus = true,
    },
    opacity = "1.0 override",
    no_blur = true,
})
-- Диалоги («Вы уверены?») непрозрачные, как tooltip, menu и dialog в picom.
hl.window_rule({
    name    = "opaque-modal",
    match   = { modal = true },
    opacity = "1.0 override",
    no_blur = true,
})

-- Окно yazi для выбора файла (xdg-desktop-portal-termfilechooser): по центру.
-- Прозрачность и размытие как у wezterm: класс входит в blur-terminal-focused.
hl.window_rule({
    name   = "termfilechooser",
    match  = { class = "^termfilechooser$" },
    float  = true,
    center = true,
    size   = { 1100, 700 },
})

-- Из примера Hyprland: убирает проблемы с перетаскиванием пустых окон Xwayland.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

------------------
---- ПРИВЯЗКИ ----
------------------

-- Соответствие rc.xml Openbox (спецификация hyprland-binds).
-- Не перенесены намеренно, сочетания остаются свободными:
--   Alt+Пробел (меню окна), Alt+Super+Пробел (корневое меню),
--   Super+T (рамки окна), Super+D (показать рабочий стол).
-- Зарезервированы за картой XKB: Super+Пробел, Alt+E, Alt+R.
local mainMod = "SUPER"
local scripts = HOME .. "/.config/hypr/scripts/"

-- Программы.
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("wezterm-gui"))
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd("rofi -show drun"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + V",      hl.dsp.exec_cmd(scripts .. "clipboard-menu"))

-- Окно.
hl.bind(mainMod .. " + C",         hl.dsp.window.close())
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + X",         hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
-- Замена сворачивания: Super+Z прячет окно в специальный стол «hidden»,
-- Super+Shift+Z показывает и скрывает этот стол.
hl.bind(mainMod .. " + Z",         hl.dsp.window.move({ workspace = "special:hidden", follow = false }))
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.workspace.toggle_special("hidden"))

-- Фокус.
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "d" }))
-- Alt+Tab с подъёмом окна наверх, как NextWindow в Openbox.
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({ next = true }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end)
hl.bind("ALT + SHIFT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next({ prev = true }))
    hl.dispatch(hl.dsp.window.bring_to_top())
end)

-- Половины рабочей области (MoveResizeTo из rc.xml). Рабочая область — монитор
-- без зон, зарезервированных слоями; отступ 10 px от краёв и между окнами.
local GAP = 10

local function vec(v)
    if type(v) ~= "table" then return 0, 0 end
    return v.x or v[1] or 0, v.y or v[2] or 0
end

-- Зарезервированные зоны монитора в порядке left, top, right, bottom.
-- Форма поля reserved в Lua-API не задокументирована, поэтому разбираются
-- три варианта; уточняется командой `hyprctl eval 'return hl.get_active_monitor().reserved'`.
local function reserved_of(mon)
    local r = mon.reserved
    if type(r) ~= "table" then return 0, 0, 0, 0 end
    if r.left or r.top or r.right or r.bottom then
        return r.left or 0, r.top or 0, r.right or 0, r.bottom or 0
    end
    if r.top_left or r.bottom_right then
        local l, t = vec(r.top_left)
        local rr, b = vec(r.bottom_right)
        return l, t, rr, b
    end
    return r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
end

local function half(side)
    return function()
        local mon = hl.get_active_monitor()
        if not mon then return end
        local mx, my = vec(mon.position)
        local mw, mh = mon.width, mon.height
        local l, t, r, b = reserved_of(mon)
        -- Рабочая область без отступов по краям.
        local ax, ay = mx + l + GAP, my + t + GAP
        local aw, ah = mw - l - r - 2 * GAP, mh - t - b - 2 * GAP
        local x, y, w, h = ax, ay, aw, ah
        if side == "left" or side == "right" then
            w = math.floor((aw - GAP) / 2)
            if side == "right" then x = ax + aw - w end
        else
            h = math.floor((ah - GAP) / 2)
            if side == "down" then y = ay + ah - h end
        end
        hl.dispatch(hl.dsp.window.float({ action = "on" }))
        hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false }))
        hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false }))
    end
end
hl.bind(mainMod .. " + SHIFT + left",  half("left"))
hl.bind(mainMod .. " + SHIFT + right", half("right"))
hl.bind(mainMod .. " + SHIFT + up",    half("up"))
hl.bind(mainMod .. " + SHIFT + down",  half("down"))

-- Рабочие столы: переход и перенос окна с переходом за ним (SendToDesktop).
for i = 1, 8 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i, follow = true }))
end

-- Мышь: перемещение и изменение размера с зажатым Super.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Блокировка: hypridle ловит сигнал logind и запускает hyprlock.
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl --no-ask-password lock-session"))

-- Скриншоты (grim, slurp, wl-copy; каталог ~/Pictures/Screenshots).
hl.bind("Print",         hl.dsp.exec_cmd(scripts .. "screenshot-screen"))
hl.bind("CTRL + Print",  hl.dsp.exec_cmd(scripts .. "screenshot-countdown"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(scripts .. "screenshot-selection"))

-- Уведомления dunst.
hl.bind("CTRL + Escape",        hl.dsp.exec_cmd("dunstctl history-pop"))
hl.bind("CTRL + Return",        hl.dsp.exec_cmd("dunstctl context"))
hl.bind("CTRL + space",         hl.dsp.exec_cmd("dunstctl close"))
hl.bind("CTRL + SHIFT + space", hl.dsp.exec_cmd("dunstctl close-all"))

-- Медиаклавиши: те же скрипты, что в Openbox (amixer, brightnessctl).
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(HOME .. "/.scripts/change-volume.sh +"),     { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(HOME .. "/.scripts/change-volume.sh -"),     { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(HOME .. "/.scripts/change-volume.sh 0"),     { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd(HOME .. "/.scripts/change-brightness.sh +"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd(HOME .. "/.scripts/change-brightness.sh -"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioStop",        hl.dsp.exec_cmd("playerctl stop"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })

-- Служебные привязки, которых в Openbox не было.
-- Выход из сессии, пока нет плиток питания.
hl.bind(mainMod .. " + M", hl.dsp.exit())
-- Переключение аппаратного и программного курсора на лету.
hl.bind(mainMod .. " + SHIFT + C", function()
    local soft = hl.get_config("cursor.no_hardware_cursors")
    hl.config({ ["cursor.no_hardware_cursors"] = not soft })
    hl.notification.create({
        text    = soft and "Курсор: аппаратный" or "Курсор: программный",
        timeout = 3000,
        icon    = "ok",
    })
end)

--------------------
---- АВТОЗАПУСК ----
--------------------

-- hyprland.start срабатывает один раз при старте композитора и не срабатывает
-- при `hyprctl reload`, поэтому защита от дублей не нужна.
--
-- Hyprland 0.56.2 импортирует WAYLAND_DISPLAY и другие переменные в systemd
-- пользователя, но graphical-session.target сам не поднимает. Это делает
-- собственная цель hyprland-session.target (~/.config/systemd/user/).
-- Через неё стартуют юниты hyprpaper, hypridle, hyprpolkitagent, voxtype.
-- Когда обновление Hyprland принесёт встроенную интеграцию (см. вики,
-- «Systemd startup»), цель удаляется командой
-- `systemctl --user revert hyprland-session.target`, а два обработчика ниже
-- (start и stop) убираются.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    -- Апплет NetworkManager как StatusNotifier: значок появится с панелью,
    -- агент секретов работает и без неё.
    hl.exec_cmd("nm-applet --indicator")
    -- История буфера обмена: текст и изображения.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- VPN axata; kozloff-de только вручную.
    hl.exec_cmd(scripts .. "vpn-up")
    hl.exec_cmd("wezterm-gui")
    hl.exec_cmd("firefox")
end)

hl.on("hyprland.shutdown", function()
    os.execute("systemctl --user stop graphical-session.target")
end)
