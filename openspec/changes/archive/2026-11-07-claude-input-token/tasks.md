## 1. Хук и спецификация

- [x] 1.1 Хук: `herdr pane report-metadata` на панели Claude Code с токеном `input_pane` после `pane split`.
- [x] 1.2 Хук: токен выставляется заново при `resume` с живой панелью буфера.
- [x] 1.3 Дельта спецификации `claude-input`, `design.md`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `openspec validate claude-input-token --strict`.

## 3. Проверка вживую (агент)

- [x] 3.1 После старта пробной сессии `herdr pane get` панели Claude Code показывает токен `input_pane` со значением `pane_id` панели nvim; после `/exit` панель nvim закрыта.
