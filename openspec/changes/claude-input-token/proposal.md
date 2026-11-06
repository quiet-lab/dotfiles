## Why

Форк herdr переводит фокус на панель Neovim с буфером ввода при выборе
workspace в Spaces и агента в Agents. Панель ввода он узнаёт по токену панели;
хук токен не ставит. Решение пользователя 7 ноября 2026.

## What Changes

- Хук `open` после создания панели буфера ставит токен `input_for` источника
  `claude-input` со значением `pane_id` панели Claude Code.
- Требование об открытии панели и его сценарий дополняются проверкой токена.
- `docs/claude-input.md`: строка о токене и его потребителях.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: токен `input_for` на панели буфера.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`, `docs/claude-input.md`.
- Панели уже идущих сессий токена не имеют до перезапуска сессии.
