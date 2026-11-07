## Why

Панель ввода Neovim переоткрывается командой `/input-reopen`, которую можно
набрать только в Claude Code. Когда зависший nvim не отвечает, нужна горячая
клавиша клиента herdr: она вызывает хук из панели в фокусе, то есть чаще всего
из панели nvim, а не панели Claude Code.

## What Changes

- Режим `reopen` хука `herdr-claude-input.sh` находит панель Claude Code по
  токену `input_pane`, а не считает `HERDR_PANE_ID` панелью Claude; предков
  процесса `reopen` не проверяет (сервер herdr запускает команду клавиши без
  процесса `claude` среди предков).
- Горячая клавиша Ctrl+Alt+R клиента herdr (таблица `[keys]` конфигурации
  herdr, действие «команда по клавише» форка) вызывает тот же хук.
- Дополняется требование «Панель буфера переоткрывается командой».
- `docs/claude-input.md`: поиск панели Claude и клавиша.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: переоткрытие панели буфера из любой панели workspace и по клавише herdr.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`,
  `dot_config/herdr/config.toml`, `docs/claude-input.md`.
