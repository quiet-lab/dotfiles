## MODIFIED Requirements

### Requirement: Панель буфера ввода открывается вместе с сессией Claude Code
Хук Claude Code `SessionStart` с событиями `startup` и `resume` MUST вызывать сценарий `~/.claude/hooks/herdr-claude-input.sh open`. Внутри herdr сценарий MUST делить панель Claude Code вниз с передачей ей фокуса так, чтобы область вывода новой панели была ровно 13 строк (`viewport_rows` в ответе `herdr pane get`), и запускать в ней процессом панели neovim с командой `ClaudeInput`. События `compact` и `clear` панель MUST NOT открывать.

#### Scenario: Запуск Claude Code в herdr
- **WHEN** в панели herdr запускается `claude`
- **THEN** под панелью Claude Code появляется панель с neovim, у неё `viewport_rows` равно 13, фокус у панели ввода, а neovim открыт в буфере `claude://input` в режиме вставки
