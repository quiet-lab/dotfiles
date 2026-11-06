## Why

Форк herdr переводит фокус на панель Neovim с буфером ввода при выборе
workspace в Spaces и агента в Agents. Панель ввода он узнаёт по токену панели
Claude Code;
хук токен не ставит.

## What Changes

- Хук `open` после создания панели буфера ставит на панель Claude Code токен
  `input_pane` источника `claude-input` со значением `pane_id` панели буфера;
  при `resume` с живой панелью буфера токен выставляется заново.
- Требование об открытии панели и его сценарий дополняются проверкой токена.
- `docs/claude-input.md`: строка о токене и его потребителях.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: токен `input_pane` на панели Claude Code.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`, `docs/claude-input.md`.
- Панели уже идущих сессий получают токен при следующем `resume`.
