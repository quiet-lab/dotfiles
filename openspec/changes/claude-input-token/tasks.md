## 1. Хук и спецификация

- [x] 1.1 Хук: `herdr pane report-metadata` с токеном `input_for` после `pane split`.
- [x] 1.2 Дельта спецификации `claude-input`, `design.md`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `openspec validate claude-input-token --strict`.

## 3. Проверка вживую (агент)

- [x] 3.1 После старта пробной сессии `herdr pane get` панели nvim показывает токен `input_for`; после `/exit` панель закрыта.
