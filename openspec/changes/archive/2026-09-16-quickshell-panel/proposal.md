# Proposal: Боковая панель на Quickshell для сессии Hyprland

## Why

Сессия Hyprland (изменение `hyprland-config`, архив 2026-09-10) пригодна для работы, но идёт без левой колонки плиток: дашборд eww остался в сессии Openbox, а его демон `eww-daemon` завязан на X11 (EWMH, xdotool, xembedsniproxy, xkb-switch). Без панели нет часов, состояния столов с иконками окон, трея, лаунчера и переключателя раскладки, к которым пользователь привык в Openbox. Оболочка Quickshell 0.3.1 выбрана при исследовании переезда и проверена на этой машине (панель на layer-shell с зоной 330 px, анимации, прозрачность слоя с размытием), поэтому колонка переносится на неё целиком.

## What Changes

- Новая конфигурация Quickshell `dot_config/quickshell/panel/` (`shell.qml` и модули по плиткам): одно окно layer-shell у левого края монитора DP-2 с зарезервированной зоной 330 px, внутри вертикальная колонка плиток в стиле Tokyo Night с теми же размерами и порядком, что у дашборда eww.
- Плитки, перенесённые один в один по поведению: питание (блокировка, выход, перезагрузка конфига, перезагрузка, выключение), часы с датой и календарём, погода wttr.in, шкалы CPU/RAM/GPU с температурами, сеть (eth, wifi, vpn) с меню действий, диски, избранное (yazi в wezterm), восемь столов с иконками окон, трей с кнопкой громкости, раскладка клавиатуры, лаунчер с фильтром.
- Источники данных переезжают с демона `eww-daemon` и X11-утилит на модули Quickshell: столы и окна — `Quickshell.Hyprland`, трей и меню — `Quickshell.Services.SystemTray` с `QsMenuAnchor`, громкость — `Quickshell.Services.Pipewire`, сеть — `Quickshell.Networking`, список приложений — `DesktopEntries`, иконки — `Quickshell.iconPath`, раскладка — события `activelayout` Hyprland. Шкалы, диски и погода остаются на скриптах через `Process` и `Timer`; скрипты копируются в `dot_config/quickshell/panel/scripts/`, скрипты eww не меняются.
- Вспомогательные окна eww (`netmenu`, `winmenu`, `hoverinfo`) становятся всплывающими окнами Quickshell (`PopupWindow`) с привязкой к плитке.
- Автозапуск сессии Hyprland запускает панель (`qs -c panel`) через пользовательский юнит systemd на цели `hyprland-session.target`; правило слоя в `hyprland.lua` включает размытие для пространства имён панели, `nm-applet` остаётся для значка в трее.
- Сессия Openbox и конфигурация eww не изменяются: обе сессии остаются рабочими до отдельного решения об удалении Openbox. Демон `eww-daemon` в сессии Hyprland не запускается; пробная конфигурация `~/.config/quickshell/nvcheck/` удаляется после запуска панели.
- **BREAKING** для сценария «Окно в половину рабочей области» спецификации hyprland-binds: числа в сценарии рассчитаны без зарезервированных зон, с панелью половины считаются от области 3510×2160; требование при этом не меняется, поскольку функция уже учитывает зоны монитора.

## Capabilities

### New Capabilities
- `qs-shell`: каркас панели Quickshell — окно layer-shell, зона 330 px, состав и геометрия колонки, стиль Tokyo Night, запуск из сессии, плитки избранного и питания, всплывающие окна.
- `qs-clock-calendar`: плитка часов, даты и календаря с навигацией по месяцам, реализованная средствами QML без демона.
- `qs-weather`: плитка погоды wttr.in с прогнозом на 3 дня и оффлайн-фолбэком.
- `qs-monitors`: круговые шкалы CPU, RAM, GPU с температурной подсветкой и плитка дисков.
- `qs-network`: строки состояния eth, wifi, vpn через `Quickshell.Networking` и NetworkManager, меню действий сети.
- `qs-workspaces`: восемь плиток столов с иконками окон из `Quickshell.Hyprland`, активация и меню окна, подсказка при наведении.
- `qs-tray-lang`: трей StatusNotifierItem с меню DBusMenu и кнопкой громкости PipeWire, переключатель раскладки по событиям Hyprland.
- `qs-launcher`: лаунчер приложений из `DesktopEntries` с фильтром, разделами, частыми приложениями и статистикой запусков.

### Modified Capabilities
- `hyprland-autostart`: в состав автозапуска добавляется панель Quickshell как юнит на `hyprland-session.target`; пробная панель nvcheck и `eww-daemon` в сессии не запускаются.
- `hyprland-config`: конфиг задаёт правило слоя для панели (размытие с учётом прозрачных промежутков между плитками); сценарий эффектов учитывает панель.

## Impact

- Новые файлы под chezmoi: `dot_config/quickshell/panel/` (QML-модули, стили, скрипты), `dot_config/systemd/user/quickshell-panel.service`.
- Правки: `dot_config/hypr/hyprland.lua` (правило слоя, автозапуск не меняется, так как панель стартует юнитом).
- Пакеты: `quickshell` 0.3.1 уже установлен; для погоды нужен `curl` (есть), для шкал `lm_sensors` и `nvidia-smi` (есть), для дисков `jq` (есть, через mise).
- Вне chezmoi: удаление `~/.config/quickshell/nvcheck/` после ввода панели в строй.
- Не затрагивается: `dot_config/eww/`, `dot_config/openbox/`, проект `~/work/pets/eww-daemon`, спецификации `eww-*`.
- Риск: Quickshell 0.3 и Hyprland 0.56 обновляются часто, API модуля Hyprland и layer-shell может измениться; конфиг привязан к версиям, зафиксированным в design.
