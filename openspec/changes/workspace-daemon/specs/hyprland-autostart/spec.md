## MODIFIED Requirements

### Requirement: Состав автозапуска
При старте сессии Hyprland MUST запускаться: обои (hyprpaper с тем же файлом, что сохранён для nitrogen), уведомления dunst, агент polkit `hyprpolkitagent`, апплет NetworkManager `nm-applet` в режиме StatusNotifier, менеджер буфера обмена cliphist с наблюдателем `wl-paste --watch` для текста и изображений, демон voxtype, hypridle, демон workspaced, панель Quickshell (конфигурация `panel`), терминал wezterm и браузер firefox. Панель MUST запускаться пользовательским юнитом systemd `quickshell-panel.service`, а демон workspaced — юнитом `workspaced.service`; оба привязаны к цели `hyprland-session.target`: одна копия на сессию, перезапуск при аварийном завершении, остановка вместе с целью; панель запускается после демона, но не зависит от него. Программы X11-сессии picom, xembedsniproxy, pasystray, clipcatd, kb_listener, xkbcomp, setxkbmap, xset и Handy.AppImage, а также дашборд eww, `eww-daemon` и пробная панель `nvcheck` MUST NOT запускаться в сессии Hyprland.

#### Scenario: Сессия запущена
- **WHEN** прошло 10 секунд после входа в сессию
- **THEN** `pgrep` находит по одному процессу hyprpaper, dunst, hyprpolkitagent, nm-applet, voxtype, hypridle, workspaced, quickshell и два наблюдателя wl-paste, панель видна у левого края экрана, а на экране открыты окна wezterm и firefox

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
