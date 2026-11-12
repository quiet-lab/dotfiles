## REMOVED Requirements

### Requirement: Предстартовая подготовка herdr
**Reason**: обновления Claude Code и herdr при старте сессии убраны по решению пользователя (herdr собирается им самим, Claude Code обновляется вручную); остаются быстрые шаги без сети.

**Migration**: источник herdr описывает «herdr из форка duty-herdr», шаги подготовки — «Быстрая предстартовая подготовка herdr».

## ADDED Requirements

### Requirement: herdr из форка duty-herdr
herdr станции MUST быть форком duty-herdr, установленным в `~/.local/bin/herdr` собственной сборкой пользователя; пакет `herdr-bin` MUST NOT быть установлен. Старт сессии MUST NOT обновлять herdr и Claude Code.

#### Scenario: Источник herdr
- **WHEN** проверяется установка herdr
- **THEN** `~/.local/bin/herdr` — бинарник форка, `pacman -Q herdr-bin` не находит пакета

#### Scenario: Вход в сессию без сети
- **WHEN** имена не разрешаются, сессия стартует
- **THEN** в журнале сессии нет вызовов `claude update` и `herdr update`

### Requirement: Быстрая предстартовая подготовка herdr
При старте сессии Hyprland, до демона workspaced, пользовательский юнит `herdr-prestart.service` MUST выполнить `~/.local/bin/handmade-scripts/herdr-prestart`: только быстрые шаги без сети — `herdr integration install claude` и чистый старт herdr. Ошибка шага MUST записываться в журнал и MUST NOT останавливать запуск демона workspaced. Ключ `--dry-run` MUST печатать шаги, ничего не меняя.

#### Scenario: Пробный запуск
- **WHEN** выполнена `herdr-prestart --dry-run`
- **THEN** сценарий печатает два шага, ни один файл не меняется, `herdr integration install claude` не выполняется

#### Scenario: Подготовка при недоступной сети
- **WHEN** имена не разрешаются (туннель `amn0` без рукопожатия), сессия стартует
- **THEN** `herdr-prestart.service` завершается меньше чем за 2 с, `workspaced.service` стартует без ожидания сети
