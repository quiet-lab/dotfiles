# hyprland-autostart Specification

## Purpose

Программы, которые сессия Hyprland запускает при старте, сетевые соединения и защита от повторного запуска.

## Requirements

### Requirement: Состав автозапуска
При старте сессии Hyprland MUST запускаться: обои (hyprpaper), агент polkit `hyprpolkitagent`, апплет NetworkManager `nm-applet` в режиме StatusNotifier, менеджер буфера обмена cliphist с наблюдателем `wl-paste --watch` для текста и изображений, демон voxtype, hypridle, демон workspaced и панель Quickshell (конфигурация `panel`). Уведомления сессии показывает сама панель (спецификация qs-notifications): отдельный демон уведомлений MUST NOT запускаться, юнит `dunst.service` MUST быть замаскирован. Окна для работы открывает демон, поднимая стартовый workspace из своего конфига (спецификация ws-sessions); конфиг Hyprland MUST NOT запускать терминал и браузер сам. Панель MUST запускаться пользовательским юнитом systemd `quickshell-panel.service`, а демон workspaced — юнитом `workspaced.service`; оба привязаны к цели `hyprland-session.target`: одна копия на сессию, перезапуск при аварийном завершении, остановка вместе с целью; панель запускается после демона, но не зависит от него.

#### Scenario: Сессия запущена
- **WHEN** прошло 10 секунд после входа в сессию
- **THEN** `pgrep` находит по одному процессу hyprpaper, hyprpolkitagent, nm-applet, voxtype, hypridle, workspaced, quickshell и два наблюдателя wl-paste, процесса dunst нет, панель видна у левого края экрана, а на экране открыты окна стартового workspace демона

#### Scenario: Конфиг перезагружен
- **WHEN** выполнена `hyprctl reload`
- **THEN** ни одна программа автозапуска не запускается повторно, число их процессов не меняется

#### Scenario: Панель упала
- **WHEN** процесс quickshell завершился аварийно
- **THEN** systemd перезапускает `quickshell-panel.service`, и панель снова видна не позднее чем через 5 секунд

#### Scenario: Демон упал
- **WHEN** процесс workspaced завершился аварийно
- **THEN** systemd перезапускает `workspaced.service` не позднее чем через 5 секунд, окна приложений остаются открытыми

#### Scenario: Выход из сессии
- **WHEN** сессия Hyprland завершена штатно
- **THEN** `quickshell-panel.service` и `workspaced.service` остановлены вместе с `hyprland-session.target`, процессов quickshell и workspaced не осталось

### Requirement: VPN при старте сессии
При старте сессии MUST подниматься VPN-соединение NetworkManager `axata`, если оно ещё не активно; перед этим сессия MUST дождаться состояния `connected` у NetworkManager, но не дольше 30 секунд. Соединение `kozloff-de` MUST NOT подниматься автоматически ни сессией, ни NetworkManager (`connection.autoconnect no`).

#### Scenario: VPN поднят
- **WHEN** прошло 30 секунд после входа в сессию при работающем проводном соединении
- **THEN** `nmcli -t -f NAME con show --active` содержит `axata` и не содержит `kozloff-de`

#### Scenario: VPN уже активен
- **WHEN** `axata` уже активно к моменту старта сессии
- **THEN** сессия не выполняет повторное подключение и не разрывает соединение

### Requirement: Блокировка экрана
Сессия MUST блокироваться командой `loginctl lock-session`: hypridle слушает сигнал logind и запускает hyprlock. Автоматическая блокировка по бездействию и выключение монитора MUST NOT включаться без отдельного решения.

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
Демон voxtype MUST запускаться при старте сессии с конфигом `~/.config/voxtype/config.toml` из chezmoi (языки `en` и `ru`), а печать распознанного текста MUST идти через wtype, независимо от активной раскладки. Уведомления voxtype (начало и конец записи, распознанный текст) MUST быть выключены: результат виден в окне, куда печатается текст.

#### Scenario: Диктовка русского текста
- **WHEN** при английской раскладке пользователь удерживает горячую клавишу voxtype и произносит фразу по-русски
- **THEN** в активное окно печатается русский текст
