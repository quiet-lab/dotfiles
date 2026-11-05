# hyprland-autostart Specification

## Purpose

Программы, которые сессия Hyprland запускает при старте, сетевые соединения и защита от повторного запуска.

## Requirements

### Requirement: Состав автозапуска
При старте сессии Hyprland MUST запускаться: обои (hyprpaper), агент polkit `hyprpolkitagent`, апплет NetworkManager `nm-applet` в режиме StatusNotifier, менеджер буфера обмена cliphist с наблюдателем `wl-paste --watch` для текста и изображений, демон voxtype, hypridle, демон workspaced и панель Quickshell (конфигурация `panel`). Уведомления сессии показывает сама панель (спецификация qs-notifications): отдельный демон уведомлений (dunst) в системе не установлен и MUST NOT устанавливаться и запускаться. Окна для работы открывает демон, поднимая стартовый workspace из своего конфига (спецификация ws-sessions); конфиг Hyprland MUST NOT запускать терминал и браузер сам. Панель MUST запускаться пользовательским юнитом systemd `quickshell-panel.service`, а демон workspaced — юнитом `workspaced.service`; оба привязаны к цели `hyprland-session.target`: одна копия на сессию, перезапуск при аварийном завершении, остановка вместе с целью; панель запускается после демона, но не зависит от него.

#### Scenario: Сессия запущена
- **WHEN** прошло 10 секунд после входа в сессию
- **THEN** `pgrep` находит по одному процессу hyprpaper, hyprpolkitagent, nm-applet, voxtype, hypridle, workspaced, quickshell и два наблюдателя wl-paste, пакета dunst в системе нет (`pacman -Q dunst` не находит пакет), панель видна у левого края экрана, а на экране открыты окна стартового workspace демона

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

### Requirement: Туннели при загрузке системы
Туннели MUST подниматься системой при загрузке, без входа в сессию: `amn0` — службой `awg-quick@amn0`, `axata` — юнитом `axata-vpn.service`, который активирует соединение от root без агента секретов, если оно не активно, и поднимает его снова после перезапуска NetworkManager. Ожидание MUST идти по событиям (`nm-online -s`, `nmcli --wait`), без циклов с паузой. Сессия MUST NOT поднимать VPN; `kozloff-de` MUST NOT подниматься автоматически.

#### Scenario: Загрузка с работающей сетью
- **WHEN** станция загружается при работающем проводном соединении
- **THEN** `systemctl is-active awg-quick@amn0 axata-vpn` даёт `active`, `nmcli -t -f NAME con show --active` содержит `axata` и не содержит `kozloff-de`

#### Scenario: VPN уже активен
- **WHEN** `axata` уже активно к моменту запуска `axata-vpn.service`
- **THEN** юнит пропускает запуск по условию и соединение не переподключает

### Requirement: Вход после туннелей
Экран входа greetd MUST ждать подъёма `amn0` и `axata` порядком systemd (юнит `tunnels-before-login.service`), поэтому herdr, его обновление в предстартовой подготовке и браузеры, которые открывает демон workspaced в сессии, стартуют уже с туннелями. Ожидание MUST быть ограничено 105 с от начала загрузки: туннель, не поднявшийся за это время, MUST NOT задерживать вход дальше и продолжает подниматься, а его значок в трее показывает состояние.

#### Scenario: Туннели подняты до входа
- **WHEN** станция загрузилась, и сессия запущена автовходом
- **THEN** в журнале загрузки `Finished` у `awg-quick@amn0` и `axata-vpn` стоит раньше запуска `greetd.service`

#### Scenario: Сервер axata недоступен
- **WHEN** сервер `axata` не отвечает при загрузке
- **THEN** экран входа появляется не позже чем через 105 с от начала загрузки, проводное соединение и `amn0` работают, а значок `axata` в трее показывает ошибку

### Requirement: Предстартовая подготовка herdr
herdr станции MUST быть форком duty-herdr из GitHub Releases `quiet-lab/duty-herdr`, установленным в `~/.local/bin/herdr`; пакет `herdr-bin` MUST NOT быть установлен. При старте сессии Hyprland, до демона workspaced, пользовательский юнит `herdr-prestart.service` MUST выполнить сценарий `~/.local/bin/handmade-scripts/herdr-prestart`: `claude update` со сроком 90 с, `herdr update` со сроком 10 с, `herdr integration install claude` и чистый старт herdr. Ошибка шага MUST записываться в журнал и MUST NOT останавливать следующие шаги и запуск демона workspaced; недоступность сети или Releases при `herdr update` MUST NOT считаться ошибкой подготовки. Ключ `--dry-run` MUST печатать шаги, ничего не меняя.

#### Scenario: Пробный запуск
- **WHEN** выполнена `herdr-prestart --dry-run`
- **THEN** сценарий печатает четыре шага, ни один файл не меняется, `claude update`, `herdr update` и `herdr integration install claude` не выполняются

#### Scenario: Claude Code не обновился
- **WHEN** `claude update` завершился ошибкой или по сроку
- **THEN** журнал юнита содержит строку об ошибке, herdr и интеграция обновлены, демон workspaced запущен

#### Scenario: Releases недоступны
- **WHEN** `herdr update` не уложился в срок или не достучался до GitHub Releases
- **THEN** журнал юнита содержит строку «herdr update не выполнен», установленная версия не изменилась, интеграция и чистый старт выполнены, код выхода сценария 0

### Requirement: Чистый старт herdr
Если сервер herdr не запущен, сценарий подготовки MUST переименовать `~/.config/herdr/session.json` в `session.json.<дата-время>` в том же каталоге и хранить не больше десяти таких копий; при запущенном сервере MUST NOT трогать файлы сессии. herdr стартового workspace MUST открываться в каталоге `~/work/telecom/axata/monorepo-ocp` (`cwd` у `[apps.herdr]`) одним пространством и MUST NOT запускать Claude Code сам (`resume_agents_on_restore = false` в `~/.config/herdr/config.toml`).

#### Scenario: Вход в сессию после загрузки
- **WHEN** сессия Hyprland запущена после загрузки, сервер herdr не запущен
- **THEN** `session.json` прежней сессии лежит копией `session.json.<дата-время>`, окно herdr показывает одно пространство в каталоге монорепозитория, процессов `claude` нет

#### Scenario: Сервер herdr уже запущен
- **WHEN** сценарий подготовки запускается при работающем сервере herdr
- **THEN** сценарий пишет «сервер запущен — session.json не трогаю», файлы `~/.config/herdr` не меняются
