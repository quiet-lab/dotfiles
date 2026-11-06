## Why

Строка ввода Claude Code — однострочный по ощущению редактор с урезанным
режимом vim: длинный многострочный запрос в ней набирать и править
неудобно. Пользователь 6 ноября 2026 сформулировал требование: «При
открытии claude code делить панель и в нижней части под claude code
открывать neovim со специальным буфером. Ввод в этот буфер транслирует
символы в строку ввода claude code, заменяя своим содержимым то, что
в строке ввода. Сохранение в этом буфере очищает буфер и передаёт enter
в строку ввода claude code. Панель neovim — высотой 13 строк».

## What Changes

- Новый сценарий хука Claude Code `herdr-claude-input.sh` (`open`
  и `close`): при старте и возобновлении сессии Claude Code внутри herdr
  делит её панель и открывает снизу панель neovim высотой ровно 13 строк
  без фокуса; при завершении сессии закрывает эту панель. Повторный старт
  для той же панели второй панели не создаёт. Вне herdr, у субагентов
  и у исполнителей duty сценарий ничего не делает.
- Регистрация сценария в `~/.claude/settings.json`: `SessionStart`
  с событиями `startup` и `resume`, `SessionEnd`.
- Локальный плагин neovim `claude-input`: команда `ClaudeInput` открывает
  буфер `claude://input`; каждое изменение буфера заменяет строку ввода
  Claude Code его содержимым, `:w` отправляет запрос (Enter) и очищает
  буфер, `:q` закрывает neovim и панель.
- Транспорт — сокет herdr из Lua (`vim.uv`), без запуска процесса
  на клавишу, без таймеров; один запрос в полёте.

## Capabilities

### New Capabilities
- `claude-input`: панель буфера ввода Claude Code в herdr и трансляция
  буфера neovim в строку ввода Claude Code.

### Modified Capabilities
—

## Impact

- `dot_claude/settings.json` (блоки `SessionStart` и `SessionEnd`),
  новый `dot_claude/hooks/executable_herdr-claude-input.sh`.
- `dot_config/nvim/lua/plugins/claude-input.lua` и локальный плагин
  `dot_config/nvim/local/claude-input/`.
- Зависимости: herdr (сокет `HERDR_SOCKET_PATH`), `jq`, neovim с LazyVim;
  Claude Code с включённым режимом vim (`editorMode = "vim"`).
