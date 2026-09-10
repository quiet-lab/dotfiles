# Proposal: Рабочий конфиг Hyprland под chezmoi

## Why

Проверка совместимости (изменение `hyprland-nvidia-check`, архив 2026-09-10) показала, что связка Hyprland 0.56 и Quickshell работает на этой машине с драйвером `nvidia-open` 610. Пробный конфиг `~/.config/hypr/hyprland.lua` живёт вне chezmoi, запускается только из текстовой консоли и не покрывает повседневную работу: в нём нет привязок клавиш Openbox, автозапуска программ, буфера обмена, скриншотов, блокировки экрана. Следующий шаг переезда — превратить пробу в рабочую сессию, которой можно пользоваться каждый день, взять её под chezmoi и запускать из менеджера входа, не затрагивая сессию Openbox.

## What Changes

- **Конфиг Hyprland под chezmoi.** Каталог `dot_config/hypr/` с `hyprland.lua` на основе пробного файла: монитор DP-2 в родном режиме, переменные окружения для NVIDIA, карта XKB из `~/.config/X11/xkb_custom` через `kb_file`, размытие, скругления и анимации, восемь рабочих столов, как в Openbox. Пробный файл в `$HOME` заменяется управляемым.
- **Запуск из lightdm.** Сессия выбирается в greeter записью `hyprland.desktop` из пакета (`/usr/bin/start-hyprland`); конфиг lightdm не меняется, `user-session=openbox` остаётся, Openbox доступен как вторая сессия. uwsm не используется: `graphical-session.target` поднимает сам Hyprland, поэтому порталы и пользовательские юниты работают без него; запись `hyprland-uwsm.desktop` остаётся в меню на будущее. Одновременно две графические сессии одного пользователя не запускаются.
- **Привязки клавиш** переносятся из `rc.xml` Openbox с теми же сочетаниями: терминал, лаунчер rofi, файловый менеджер, закрытие и плавающий режим окна, переключение и перенос окон между столами 1–8, перемещение фокуса стрелками, полноэкранный режим, блокировка, буфер обмена, уведомления dunst, медиаклавиши playerctl, громкость, яркость, скриншоты. Переключение раскладок Alt+E, Alt+R и Win+Пробел остаётся за картой XKB, композитор эти сочетания не занимает.
- **Автозапуск сессии.** Из Hyprland запускаются: обои (hyprpaper с тем же файлом, что у nitrogen), dunst, агент polkit (`hyprpolkitagent`), nm-applet как StatusNotifier, менеджер буфера обмена (cliphist с `wl-paste --watch`), демон voxtype (вместо Handy.AppImage), hypridle с hyprlock для блокировки, wezterm, firefox. При старте поднимается VPN `axata`; `kozloff-de` автоматически не запускается. picom, xembedsniproxy, pasystray, clipcat, kb_listener, xset и xkbcomp в сессии Hyprland не нужны.
- **Скрипты горячих клавиш.** Скрипты громкости (amixer через PipeWire) и яркости (brightnessctl) от сервера отображения не зависят и используются как есть. Скрипты скриншотов написаны под X11 (scrot, xclip), для Hyprland нужны версии на grim, slurp и wl-copy; версии X11 в `dot_scripts/` остаются для Openbox.
- **Не входит в изменение** (отдельные изменения): панель на Quickshell и перенос плиток eww, Lua-раскладка зон окон, удаление сессии Openbox и eww, переход на uwsm. В переходный период сессия Hyprland работает без левой колонки: рабочие столы переключаются с клавиатуры, программы запускаются через rofi. Предположение: если колонка нужна раньше переноса на Quickshell, это оформляется отдельным изменением «eww поверх Hyprland».
- Пробная панель `~/.config/quickshell/nvcheck/` не запускается из сессии и остаётся в `$HOME` как заготовка для изменения про панель.

## Capabilities

### New Capabilities

- `hyprland-config`: состав и размещение конфига Hyprland под chezmoi, монитор, окружение, карта XKB, эффекты, рабочие столы, правила окон.
- `hyprland-binds`: горячие клавиши сессии Hyprland, соответствие сочетаниям Openbox, сочетания, зарезервированные за XKB.
- `hyprland-autostart`: программы, запускаемые при старте сессии Hyprland, порядок и защита от дублей, VPN, замены X11-компонентов.

### Modified Capabilities

- `hyprland-session`: требование «Изоляция пробной сессии» заменяется требованием о постоянном запуске из lightdm (выбор сессии в greeter, конфиг lightdm и сессия Openbox не изменяются, одновременный запуск двух сессий исключён); требование «Окружение клиентов для NVIDIA» дополняется тем, что переменные задаются в управляемом конфиге.

## Impact

- **Пакеты**: устанавливаются `hyprpaper`, `hypridle`, `hyprlock`, `cliphist`, `wl-clipboard`, `grim`, `slurp`, `xdg-desktop-portal-termfilechooser` (AUR, выбор файла через yazi из mise); уже есть `hyprland`, `xdg-desktop-portal-hyprland`, `hyprpolkitagent`, `quickshell`, `voxtype`, `wtype`, `rofi`, `dunst`, `playerctl`, `wezterm` (пересобран с Wayland).
- **Файлы chezmoi**: новые `dot_config/hypr/hyprland.lua` и скрипты Wayland для горячих клавиш (место определяется в design), возможно `dot_config/hypr/hyprpaper.conf`, `hypridle.conf`, `hyprlock.conf`; `dot_config/openbox/`, `dot_config/eww/`, `dot_scripts/` не меняются.
- **Файлы в `$HOME` вне chezmoi**: пробный `~/.config/hypr/hyprland.lua` заменяется управляемым; `~/.config/quickshell/nvcheck/` не изменяется.
- **Системные настройки**: конфиг lightdm не меняется; в NetworkManager у `kozloff-de` уже выключено автоподключение (сделано 2026-09-10 для обеих сессий).
- **Существующие системы**: сессия Openbox, eww и eww-daemon продолжают работать при входе в Openbox; в сессии Hyprland они не запускаются.
- **Спецификации**: новые `hyprland-config`, `hyprland-binds`, `hyprland-autostart`; дельта к `hyprland-session`.
