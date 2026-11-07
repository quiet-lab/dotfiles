## Why

Запасной путь хука панели ввода (herdr без `pane activate`) нужен был до
выпуска herdr с этой командой. Выпуск duty-v0.9.5.7 её содержит, других
серверов herdr у станции нет.

## What Changes

- Хук `open` открывает панель только основным путём: `pane split --no-focus`,
  затем `pane activate`. Выбор `active_ws` по `focused` и переменная
  `use_activate` снимаются.
- Нет команды `herdr pane activate` — хук пишет ошибку в stderr и панель
  не открывает.
- Требование об открытии панели: убрано условие «если команды нет», сценарий
  «без pane activate» заменён сценарием ошибки.
- `docs/claude-input.md`: запасной путь удалён.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: фокус только через `herdr pane activate`.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`, `docs/claude-input.md`.
