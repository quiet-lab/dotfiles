# hyprland-autostart Specification

## Purpose

Программы, которые сессия Hyprland запускает при старте, замены X11-компонентов из автозапуска Openbox, сетевые соединения и защита от повторного запуска.

## Requirements

### Requirement: Состав автозапуска
При старте сессии Hyprland MUST запускаться: обои (hyprpaper с тем же файлом, что сохранён для nitrogen), уведомления dunst, агент polkit `hyprpolkitagent`, апплет NetworkManager `nm-applet` в режиме StatusNotifier, менеджер буфера обмена cliphist с наблюдателем `wl-paste --watch` для текста и изображений, демон voxtype, hypridle, терминал wezterm и браузер firefox. Программы X11-сессии picom, xembedsniproxy, pasystray, clipcatd, kb_listener, xkbcomp, setxkbmap, xset и Handy.AppImage MUST NOT запускаться в сессии Hyprland.

#### Scenario: Сессия запущена
- **WHEN** прошло 10 секунд после входа в сессию
- **THEN** `pgrep` находит по одному процессу hyprpaper, dunst, hyprpolkitagent, nm-applet, voxtype, hypridle и два наблюдателя wl-paste, а на экране открыты окна wezterm и firefox

#### Scenario: Конфиг перезагружен
- **WHEN** выполнена `hyprctl reload`
- **THEN** ни одна программа автозапуска не запускается повторно, число их процессов не меняется

### Requirement: VPN при старте сессии
При старте сессии MUST подниматься VPN-соединение NetworkManager `axata`, если оно ещё не активно; перед этим сессия MUST дождаться состояния `connected` у NetworkManager, но не дольше 30 секунд. Соединение `kozloff-de` MUST NOT подниматься автоматически ни сессией, ни NetworkManager (`connection.autoconnect no`).

#### Scenario: VPN поднят
- **WHEN** прошло 30 секунд после входа в сессию при работающем проводном соединении
- **THEN** `nmcli -t -f NAME con show --active` содержит `axata` и не содержит `kozloff-de`

#### Scenario: VPN уже активен
- **WHEN** `axata` уже активно к моменту старта сессии
- **THEN** сессия не выполняет повторное подключение и не разрывает соединение

### Requirement: Блокировка экрана
Сессия MUST блокироваться командой `loginctl lock-session`: hypridle слушает сигнал logind и запускает hyprlock. Автоматическая блокировка по бездействию и выключение монитора MUST NOT включаться без отдельного решения, как и в сессии Openbox.

#### Scenario: Блокировка по сигналу logind
- **WHEN** выполнена `loginctl lock-session`
- **THEN** появляется экран hyprlock, после ввода пароля все окна сохранены

### Requirement: Порталы и окружение systemd
Hyprland MUST передавать `WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP` и `HYPRLAND_INSTANCE_SIGNATURE` в окружение пользовательского systemd и D-Bus, чтобы `xdg-desktop-portal-hyprland` и другие пользовательские юниты запускались по требованию. Сессия MUST активировать `graphical-session.target` без uwsm.
Интерфейс FileChooser портала MUST обслуживать `xdg-desktop-portal-termfilechooser` с yazi в отдельном окне wezterm (класс `termfilechooser`): выбор бэкендов задаёт `~/.config/xdg-desktop-portal/hyprland-portals.conf`, настройки бэкенда — `~/.config/xdg-desktop-portal-termfilechooser/config`, оба под chezmoi. Сессия MUST задавать `GTK_USE_PORTAL=1`, чтобы GTK-приложения и Firefox запрашивали файл через портал.

#### Scenario: Портал доступен
- **WHEN** в сессии запрошен выбор файла или демонстрация экрана через портал
- **THEN** `systemctl --user status xdg-desktop-portal-hyprland` показывает работающую службу, а `systemctl --user is-active graphical-session.target` даёт `active`

#### Scenario: Выбор файла через yazi
- **WHEN** приложение (Firefox по Ctrl+O или запрос `org.freedesktop.portal.FileChooser.OpenFile` по D-Bus) запрашивает выбор файла
- **THEN** открывается плавающее окно wezterm класса `termfilechooser` с yazi по центру экрана, `systemctl --user is-active xdg-desktop-portal-termfilechooser` даёт `active`, выбранный в yazi файл попадает в приложение, а выход из yazi по q отменяет запрос без ошибок в журнале портала

#### Scenario: Сохранение файла через yazi
- **WHEN** приложение запрашивает сохранение файла с предложенным именем
- **THEN** в предложенном каталоге появляется файл с этим именем и инструкцией внутри, yazi открывается с курсором на нём, а после Enter приложение записывает содержимое в выбранный файл; выход по q отменяет сохранение и удаляет файл-подсказку

### Requirement: Голосовой ввод
Демон voxtype MUST запускаться при старте сессии с конфигом `~/.config/voxtype/config.toml` из chezmoi (языки `en` и `ru`), а печать распознанного текста MUST идти через wtype, независимо от активной раскладки.

#### Scenario: Диктовка русского текста
- **WHEN** при английской раскладке пользователь удерживает горячую клавишу voxtype и произносит фразу по-русски
- **THEN** в активное окно печатается русский текст
