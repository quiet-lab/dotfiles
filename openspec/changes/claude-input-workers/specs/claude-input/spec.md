## MODIFIED Requirements

### Requirement: Сценарий хука не действует вне своей области
Сценарий MUST ничего не делать и завершаться с кодом 0 вне herdr (`HERDR_ENV` не равна 1 или не задана `HERDR_PANE_ID`), у субагентов (поле `agent_id` во входе хука), при высоте панели Claude Code меньше 20 строк и при любой ошибке.

#### Scenario: Исполнитель duty
- **WHEN** Claude Code запущен в панели workspace с заданной `DUTY_TASK`
- **THEN** панель буфера создаётся так же, как в корневом workspace

#### Scenario: Вне herdr
- **WHEN** Claude Code запущен в терминале без herdr
- **THEN** сценарий ничего не выводит и завершается с кодом 0
