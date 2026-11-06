## Why

Хук `herdr-claude-input.sh` не действует у исполнителей duty (задана `DUTY_TASK`),
поэтому в дочерних workspace нет панели ввода Neovim. Решение пользователя
6 ноября 2026: любая сессия Claude Code в herdr, включая исполнителей задач
duty, получает панель ввода так же, как сессия в корневом workspace;
постановка задачи агенту не должна отличаться от постановки в главном workspace.

## What Changes

- Требование области действия `claude-input` перестаёт исключать исполнителей
  duty; сценарий «Исполнитель duty» заменяется сценарием о создании панели
  в дочернем workspace.
- Из хука убирается проверка `DUTY_TASK`; исключения субагентов, вне herdr,
  низкой панели и ошибок остаются.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: область действия хука.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`, `docs/claude-input.md`.
