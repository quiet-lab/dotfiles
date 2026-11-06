## 1. Хук и спецификация

- [x] 1.1 Хук: `pane split --no-focus` и `pane activate`; запасной путь по `focused` в `workspace list`.
- [x] 1.2 Дельта спецификации `claude-input`, `design.md`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `openspec validate claude-input-focus --strict`.

## 3. Проверка вживую (агент)

- [x] 3.1 В своём (активном у клиента) workspace панель nvim с `focused: true`.
- [x] 3.2 В невидимом workspace без `pane activate`: клиент не переключён, панель nvim открыта, фокус у Claude.
