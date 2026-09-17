-- Рабочий конфиг Hyprland (изменение OpenSpec hyprland-config).
-- Источник: ~/.local/share/chezmoi/dot_config/hypr/hyprland.lua, в $HOME
-- попадает через `chezmoi apply`. Запуск: greetd с tuigreet (изменение
-- greetd-login, конфиг system/greetd/config.toml, команда start-hyprland).
-- Перезагрузка: `hyprctl reload`.
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
-- Тема Qt (раньше задавалась в ~/.xprofile сессии X11).
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
-- GTK-приложения и Firefox (режим «auto») выбирают файлы через портал, а портал
-- FileChooser отдан yazi (~/.config/xdg-desktop-portal/hyprland-portals.conf).
hl.env("GTK_USE_PORTAL", "1")
hl.env("LESSHISTFILE", "/dev/null")
-- greetd не задаёт тип сессии, а Hyprland 0.56 эту переменную не выставляет;
-- по ней клиенты (Qt, Electron, портал) отличают Wayland-сессию.
hl.env("XDG_SESSION_TYPE", "wayland")
-- ~/.local/bin (wezterm, workspaced), ~/.bun/bin и shims mise (herdr, nvim для
-- neovide, jq для панели, yazi для портала): greetd запускает сессию без
-- login-оболочки, ~/.profile он читает, а .bashrc с `mise activate` — нет,
-- поэтому PATH дополняется здесь.
-- Каталог добавляется только если его ещё нет: hl.env меняет окружение самого
-- Hyprland, и без проверки каждый `hyprctl reload` удлинял бы PATH повторами.
local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
local extra_dirs = { HOME .. "/.bun/bin", HOME .. "/.local/bin", HOME .. "/.local/bin/handmade-scripts", HOME .. "/.local/share/mise/shims" }
for i = #extra_dirs, 1, -1 do
    if not (":" .. path .. ":"):find(":" .. extra_dirs[i] .. ":", 1, true) then
        path = extra_dirs[i] .. ":" .. path
    end
end
hl.env("PATH", path)

---------------
---- ВВОД ----
---------------

-- Карта XKB целиком из файла. Переключение раскладок делает сама карта:
-- Win+Пробел по кругу, Alt+E фиксирует US, Alt+R фиксирует RU.
-- Ни одна привязка ниже не должна занимать эти сочетания.
hl.config({
    input = {
        kb_file      = HOME .. "/.config/X11/xkb_custom",
        -- Фокус только кликом по окну, как в Openbox: наведение курсора фокус не
        -- переводит (2 — курсор и клавиатурный фокус разделены, колесо идёт окну под
        -- курсором), переход между плавающими окнами наведением тоже выключен.
        follow_mouse = 2,
        float_switch_override_focus = 0,
        sensitivity  = 0,
    },
    -- Курсор не переносится к окну при смене фокуса (активация из плитки стола,
    -- Alt+Tab): он остаётся там, где был.
    cursor = {
        no_warps = true,
    },
    -- Слой с клавиатурой «по требованию» (поле фильтра панели) не удерживает
    -- клавиатуру при клике по окну: клик по окну возвращает ему ввод.
    misc = {
        layers_hog_keyboard_focus = false,
        -- Запрос активации от приложения (xdg-activation: клик по уведомлению
        -- Telegram, ссылка из другой программы) переводит фокус на его окно
        -- и стол; иначе запрос остаётся без ответа.
        focus_on_activate = true,
    },
})

-------------
---- ВИД ----
-------------

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 12,
        -- Рамка 1 px, как у плиток панели (Tile.qml, border.width).
        border_size = 1,
        -- Рамка активного окна того же цвета, что рамки плиток панели (yellow
        -- Tokyo Night, Theme.tileBorder); неактивная — тёмно-зелёная.
        col = {
            active_border   = "rgba(e0af68ee)",
            inactive_border = "rgba(2d6a4fee)",
        },
        -- Мозаика dwindle доступна через Super+Shift+V; по умолчанию окна
        -- плавающие (правило ниже), как в Openbox.
        layout = "dwindle",
    },
    -- Прозрачность, размытие и тени повторяют прежние правила picom из
    -- X11-сессии (удалена): окно в фокусе 0.9, без фокуса 0.7, полноэкранное
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
        -- Аппаратный курсор проверен без артефактов.
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

-- Все окна открываются плавающими, как в Openbox; по ячейкам workspace их
-- расставляет демон workspaced (спецификация ws-daemon), собственная
-- раскладка зон не планируется. Мозаика по Super+Shift+V.
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
-- Браузеры и видеоплееры непрозрачные и без размытия всегда, в фокусе и без него:
-- страница и видео не должны просвечивать. Браузеры работают нативно под
-- Wayland (класс chromium, google-chrome, yandex-browser), приложения Chrome —
-- crx_<id>; под Xwayland Chromium отдавал класс Chromium-browser.
hl.window_rule({
    name    = "opaque-media",
    match   = {
        class = "(?i)^(firefox|zen|cachy-browser|yandex-browser|google-chrome|chromium(-browser)?|crx_.*|mpv|vlc|smplayer|mplayer|gnome-mplayer)$",
    },
    opacity = "1.0 override",
    no_blur = true,
})
-- Игры непрозрачные в фокусе; без фокуса общие 0.7.
hl.window_rule({
    name    = "opaque-games-focused",
    match   = {
        class = "(?i)^gamescope$|^steam_app_|[.]exe$",
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

----------------
---- ОБХОДЫ ----
----------------

-- Браузеры на Chromium при выходе из полноэкранного видео шлют композитору
-- два запроса подряд: снять fullscreen и тут же развернуть окно (maximized),
-- и плавающее окно остаётся на весь экран через раз (обсуждение Hyprland
-- #13322; на 0.56.2 события fullscreen 0 и 1 приходят в одну миллисекунду).
-- Переход в maximized в первые 50 мс после выхода из fullscreen отменяется,
-- и окно возвращается к прежним положению и размеру.
local fullscreen_just_left = false
hl.on("window.fullscreen", function(w)
    local mode = w.fullscreen
    if mode == 0 then
        fullscreen_just_left = true
        hl.timer(function() fullscreen_just_left = false end, { timeout = 50, type = "oneshot" })
    elseif mode == 1 and fullscreen_just_left then
        fullscreen_just_left = false
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = w }))
    end
end)

-----------------------
---- ПРАВИЛА СЛОЁВ ----
-----------------------

-- Панель Quickshell (пространство имён panel, спецификация qs-shell): размытие
-- под плитками. Заливка плиток имеет альфу 0.9, промежутки между ними полностью
-- прозрачны; порог ignore_alpha ниже альфы плиток, поэтому промежутки не
-- размываются и не затемняются. Непрозрачность слоя правилом не задаётся —
-- её несёт заливка плиток.
hl.layer_rule({
    name         = "panel-blur",
    match        = { namespace = "^panel$" },
    blur         = true,
    ignore_alpha = 0.2,
})

------------------
---- ПРИВЯЗКИ ----
------------------

-- Все привязки и цепочки клавиш сессии задаёт ~/.config/workspaced/config.toml
-- (спецификации hyprland-binds и ws-config); собственных hl.bind в этом файле
-- нет. Код Lua печатает `workspaced keys --lua`, удачный результат команда
-- сохраняет в ~/.local/state/workspaced/keys.lua. Если команда недоступна или
-- конфиг демона сломан, загружается сохранённая копия, причина уходит в журнал
-- (`hyprctl rollinglog`, метка [Lua]) и в уведомление; без копии сессия остаётся
-- без привязок, о чём тоже сообщает уведомление. Ошибка привязок не должна
-- ломать перезагрузку остального конфига.
do
    local function notify(msg, icon)
        print("workspaced: " .. msg)
        hl.notification.create({ text = "workspaced: " .. msg, timeout = 8000, icon = icon or "error" })
    end
    local env = setmetatable({ hl = hl }, { __index = _G })
    -- Выполнить код привязок; nil при успехе, иначе текст ошибки. Сообщение
    -- демона или оболочки об ошибке разбором как Lua не пройдёт и попадёт в текст.
    local function run(code, name)
        local chunk, err = load(code, name, "t", env)
        if not chunk then return (code:match("^[^\n]*") or tostring(err)) end
        local ok, rerr = pcall(chunk)
        if not ok then return tostring(rerr) end
        return nil
    end
    -- Код завершения команды недоступен: Hyprland сам подбирает дочерние
    -- процессы, и pclose получает ECHILD, поэтому признак успеха — вывод.
    local pipe = io.popen(HOME .. "/.local/bin/workspaced keys --lua 2>&1")
    local code = pipe and pipe:read("a") or ""
    if pipe then pipe:close() end
    local err
    if code == "" then
        err = "workspaced keys --lua ничего не вернула"
    else
        err = run(code, "workspaced keys")
    end
    if err then
        local f = io.open(HOME .. "/.local/state/workspaced/keys.lua", "r")
        local copy = f and f:read("a") or ""
        if f then f:close() end
        if copy == "" then
            notify("привязки не загружены, копии нет: " .. err)
        else
            local cerr = run(copy, "workspaced keys.lua")
            if cerr then
                notify("привязки не загружены, копия тоже с ошибкой: " .. cerr)
            else
                notify("загружена копия привязок, конфиг с ошибкой: " .. err, "warning")
            end
        end
    end
end

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
local scripts = HOME .. "/.local/bin/handmade-scripts/"

hl.on("hyprland.start", function()
    -- Переменные, заданные выше через hl.env, Hyprland в окружение пользовательского
    -- systemd не передаёт (сам он передаёт только WAYLAND_DISPLAY, DISPLAY и
    -- XDG_CURRENT_DESKTOP). Демон workspaced и его приложения (браузеры, neovide)
    -- живут в этом окружении, поэтому без передачи они не видели ни типа сессии,
    -- ни переменных NVIDIA, ни настроек Qt и портала.
    hl.exec_cmd("systemctl --user import-environment XDG_SESSION_TYPE LIBVA_DRIVER_NAME __GLX_VENDOR_LIBRARY_NAME NVD_BACKEND ELECTRON_OZONE_PLATFORM_HINT MOZ_DISABLE_RDD_SANDBOX QT_QPA_PLATFORMTHEME GTK_USE_PORTAL")
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    -- Апплет NetworkManager как StatusNotifier: значок появится с панелью,
    -- агент секретов работает и без неё.
    hl.exec_cmd("nm-applet --indicator")
    -- История буфера обмена: текст и изображения.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- VPN axata; kozloff-de только вручную.
    hl.exec_cmd(scripts .. "vpn-up")
    -- Окна для работы открывает демон workspaced, поднимая стартовый
    -- workspace из своего конфига ([startup]); терминал и браузер здесь не нужны.
end)

hl.on("hyprland.shutdown", function()
    os.execute("systemctl --user stop graphical-session.target")
end)
