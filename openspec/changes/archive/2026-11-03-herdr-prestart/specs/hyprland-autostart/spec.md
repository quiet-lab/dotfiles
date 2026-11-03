## ADDED Requirements

### Requirement: Обновление herdr при загрузке
Пакет AUR `herdr-bin` MUST обновляться системой при загрузке юнитом `herdr-update.service`: юнит сравнивает версию в AUR (RPC v5) с установленной (`pacman -Q herdr-bin`) и при новой собирает пакет `makepkg` от пользователя, а ставит `pacman -U` от root. Без сети или при ошибке юнит MUST записать причину в журнал и MUST NOT менять установленный пакет.

#### Scenario: Новой версии нет
- **WHEN** версия `herdr-bin` в AUR совпадает с установленной
- **THEN** `journalctl -b -u herdr-update` содержит строку о последней версии, пакет не пересобирался

#### Scenario: В AUR новая версия
- **WHEN** версия `herdr-bin` в AUR новее установленной
- **THEN** после загрузки `pacman -Q herdr-bin` показывает версию из AUR, а журнал юнита — строку об обновлении

#### Scenario: Сети нет
- **WHEN** AUR не отвечает при загрузке
- **THEN** юнит завершается с записью в журнале, установленный пакет не меняется

### Requirement: Вход после обновления herdr
`herdr-update.service` MUST запускаться после `network-online.target` и туннеля `amn0` и до `greetd.service`. Экран входа MUST ждать его порядком systemd, без циклов с паузой, и не дольше 240 с от начала загрузки; сборка, не уложившаяся в этот срок, доделывается после входа.

#### Scenario: Долгое скачивание
- **WHEN** скачивание новой версии при загрузке идёт дольше срока
- **THEN** экран входа появляется не позже чем через 240 с от начала загрузки, а юнит продолжает работу и пишет итог в журнал

### Requirement: Предстартовая подготовка herdr
При старте сессии Hyprland, до демона workspaced, пользовательский юнит `herdr-prestart.service` MUST выполнить сценарий `~/.local/bin/handmade-scripts/herdr-prestart`: `claude update` со сроком 90 с, `herdr integration install claude` и чистый старт herdr. Ошибка шага MUST записываться в журнал и MUST NOT останавливать следующие шаги и запуск демона workspaced. Ключ `--dry-run` MUST печатать шаги, ничего не меняя.

#### Scenario: Пробный запуск
- **WHEN** выполнена `herdr-prestart --dry-run`
- **THEN** сценарий печатает три шага, ни один файл не меняется, `claude update` и `herdr integration install claude` не выполняются

#### Scenario: Claude Code не обновился
- **WHEN** `claude update` завершился ошибкой или по сроку
- **THEN** журнал юнита содержит строку об ошибке, интеграция herdr обновлена, демон workspaced запущен

### Requirement: Чистый старт herdr
Если сервер herdr не запущен, сценарий подготовки MUST переименовать `~/.config/herdr/session.json` в `session.json.<дата-время>` в том же каталоге и хранить не больше десяти таких копий; при запущенном сервере MUST NOT трогать файлы сессии. herdr стартового workspace MUST открываться в каталоге `~/work/telecom/axata/monorepo-ocp` (`cwd` у `[apps.herdr]`) одним пространством и MUST NOT запускать Claude Code сам (`resume_agents_on_restore = false` в `~/.config/herdr/config.toml`).

#### Scenario: Вход в сессию после загрузки
- **WHEN** сессия Hyprland запущена после загрузки, сервер herdr не запущен
- **THEN** `session.json` прежней сессии лежит копией `session.json.<дата-время>`, окно herdr показывает одно пространство в каталоге монорепозитория, процессов `claude` нет

#### Scenario: Сервер herdr уже запущен
- **WHEN** сценарий подготовки запускается при работающем сервере herdr
- **THEN** сценарий пишет «сервер запущен — session.json не трогаю», файлы `~/.config/herdr` не меняются
