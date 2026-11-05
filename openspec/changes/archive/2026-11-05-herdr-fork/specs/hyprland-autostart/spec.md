## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Обновление herdr при загрузке
**Reason**: herdr станции — форк из `~/.local/bin`, обновляется `herdr update` в предстартовой подготовке; пакет AUR `herdr-bin` и системный юнит удалены.
**Migration**: `herdr-prestart` выполняет `herdr update`; `herdr-update.service` отключается и удаляется, пакет `herdr-bin` удаляется.

### Requirement: Вход после обновления herdr
**Reason**: системного юнита обновления нет, экран входа ждёт только туннели.
**Migration**: порядок входа — требование «Вход после туннелей».
