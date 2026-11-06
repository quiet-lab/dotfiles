## MODIFIED Requirements

### Requirement: Панель буфера ввода открывается вместе с сессией Claude Code
Хук Claude Code `SessionStart` с событиями `startup` и `resume` MUST вызывать сценарий `~/.claude/hooks/herdr-claude-input.sh open`. Внутри herdr сценарий MUST делить панель Claude Code вниз так, чтобы область вывода новой панели была ровно 13 строк (`viewport_rows` в ответе `herdr pane get`), и запускать в ней процессом панели neovim с командой `ClaudeInput`. После открытия фокус MUST быть у панели ввода, а клиент пользователя, смотрящий другой workspace, MUST NOT переключаться на workspace сессии. Если команды `herdr pane activate` нет, сценарий MUST отдавать фокус панели ввода только в workspace, активном у клиента; в остальных workspace фокус остаётся у панели Claude Code. События `compact` и `clear` панель MUST NOT открывать.

#### Scenario: Запуск Claude Code в herdr
- **WHEN** в панели herdr запускается `claude` в workspace, который смотрит клиент
- **THEN** под панелью Claude Code появляется панель с neovim, у неё `viewport_rows` равно 13, фокус у панели ввода, а neovim открыт в буфере `claude://input` в режиме вставки

#### Scenario: Запуск Claude Code в невидимом workspace при наличии pane activate
- **WHEN** `claude` запускается в workspace, который клиент не смотрит, и команда `herdr pane activate` есть
- **THEN** фокус внутри этого workspace у панели с neovim, активный workspace клиента не изменился

#### Scenario: Запуск Claude Code в невидимом workspace без pane activate
- **WHEN** `claude` запускается в workspace, который клиент не смотрит, и команды `herdr pane activate` нет
- **THEN** панель с neovim открыта, фокус остаётся у панели Claude Code, активный workspace клиента не изменился
