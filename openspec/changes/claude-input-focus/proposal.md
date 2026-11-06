## Why

Панель ввода Neovim открывается с фокусом у панели Claude Code, и пользователю
приходится переводить фокус вручную. Решение пользователя 6 ноября 2026:
после открытия панели ввода фокус переходит на неё.

## What Changes

- Требование об открытии панели и его сценарий: вместо «без передачи фокуса,
  фокус остаётся у Claude Code» — «фокус переходит на панель ввода».
- Хук делит панель с `--focus` вместо `--no-focus`.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: фокус после открытия панели.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`, `docs/claude-input.md`.
