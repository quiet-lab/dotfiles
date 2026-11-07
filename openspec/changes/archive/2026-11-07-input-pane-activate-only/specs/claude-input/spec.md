## MODIFIED Requirements

### Requirement: Панель буфера ввода открывается вместе с сессией Claude Code
Хук Claude Code `SessionStart` с событиями `startup` и `resume` MUST вызывать сценарий `~/.claude/hooks/herdr-claude-input.sh open`. Внутри herdr сценарий MUST делить панель Claude Code вниз так, чтобы область вывода новой панели была ровно 13 строк (`viewport_rows` в ответе `herdr pane get`), и запускать в ней процессом панели neovim с командой `ClaudeInput`. После открытия фокус MUST быть у панели ввода, а клиент пользователя, смотрящий другой workspace, MUST NOT переключаться на workspace сессии. Фокус MUST отдаваться командой `herdr pane activate` после запуска neovim; если этой команды нет, сценарий MUST выводить сообщение об ошибке в stderr, MUST завершаться с кодом 1 и MUST NOT открывать панель. После открытия панели буфера панель Claude Code MUST нести токен `input_pane` источника `claude-input` со значением `pane_id` панели буфера (`herdr pane get <панель Claude>`, поле `tokens`); при возобновлении с живой панелью буфера токен MUST быть выставлен заново; ошибка установки токена (herdr без `--token`) MUST NOT прерывать хук. События `compact` и `clear` панель MUST NOT открывать.

#### Scenario: Запуск Claude Code в herdr
- **WHEN** в панели herdr запускается `claude` в workspace, который смотрит клиент
- **THEN** под панелью Claude Code появляется панель с neovim, у неё `viewport_rows` равно 13, фокус у панели ввода, а neovim открыт в буфере `claude://input` в режиме вставки, а `herdr pane get` панели Claude Code показывает токен `input_pane` со значением `pane_id` панели ввода

#### Scenario: Запуск Claude Code в невидимом workspace при наличии pane activate
- **WHEN** `claude` запускается в workspace, который клиент не смотрит, и команда `herdr pane activate` есть
- **THEN** фокус внутри этого workspace у панели с neovim, активный workspace клиента не изменился

#### Scenario: Запуск Claude Code в невидимом workspace без pane activate
- **WHEN** `claude` запускается в любом workspace herdr, у которого нет команды `herdr pane activate`
- **THEN** хук пишет сообщение об ошибке в stderr, панель с neovim не открывается, код выхода 1 (ненулевой код нужен, чтобы Claude Code показал stderr SessionStart; сессия продолжается)

#### Scenario: Возобновление сессии с живой панелью буфера
- **WHEN** сессия возобновляется (`resume`) в панели Claude Code, у которой панель буфера жива в том же workspace
- **THEN** новая панель не создаётся, а `herdr pane get` панели Claude Code показывает токен `input_pane` со значением `pane_id` живой панели буфера

#### Scenario: herdr без `--token`
- **WHEN** `herdr pane report-metadata` отвергает `--token`
- **THEN** хук продолжает работу, панель с neovim открыта, ошибки не выводится
