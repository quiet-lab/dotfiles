## MODIFIED Requirements

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
