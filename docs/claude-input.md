# Буфер ввода Claude Code в neovim

Поведение задаёт спецификация `claude-input` (`openspec/specs/claude-input/`),
выбор последовательностей и замеры — `design.md` изменения
`claude-input-buffer` в `openspec/changes/archive/`.
Здесь — устройство и проверка после обновления Claude Code.

## Устройство

- Хук `~/.claude/hooks/herdr-claude-input.sh` (источник
  `dot_claude/hooks/executable_herdr-claude-input.sh`) вызывается из
  `~/.claude/settings.json`: `open` по `SessionStart` (`startup`, `resume`),
  `close` по `SessionEnd`. `open` делит панель Claude Code в herdr вниз,
  выводит новую панель на 13 строк и запускает в ней `exec nvim +ClaudeInput`
  с переменной `CLAUDE_INPUT_PANE` — идентификатором панели Claude Code.
- Соответствие панелей лежит в `~/.local/state/claude-input/<панель>`
  (двоеточие в имени заменено подчёркиванием). Файл, оставшийся после
  обрыва, не мешает: `open` проверяет, жива ли записанная панель.
- Плагин neovim — локальный каталог `~/.config/nvim/local/claude-input`
  (модуль `claude_input`), спецификация lazy.nvim —
  `lua/plugins/claude-input.lua`. Он пишет в сокет herdr
  (`HERDR_SOCKET_PATH`) напрямую через `vim.uv`, по соединению на запрос.

## Проверка после обновления Claude Code

Замена строки ввода опирается на режим vim Claude Code, на распознавание
вставки по длине куска (~800 знаков) и на понимание Esc в кодировке
`CSI 27 u`. После обновления Claude Code строку ввода стоит сверить
с буфером: набрать многострочный текст, поправить его в середине и
посмотреть строку ввода командой `herdr pane read <панель Claude> --source
visible`. Точный снимок строки ввода даёт Ctrl+G в Claude Code, запущенном
с `VISUAL`, указывающим на сценарий, который копирует свой аргумент в файл
и сразу выходит: Claude Code передаёт редактору файл с текущим запросом.
Без такой подмены Ctrl+G открывает редактор пользователя (`VISUAL=neovide`)
отдельным окном. Enter в пробах — только с местной командой `/help`:
обычный текст и `!команда` уходят модели.
