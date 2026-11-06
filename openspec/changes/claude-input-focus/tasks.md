## 1. Хук и спецификация

- [x] 1.1 Хук: `pane split --focus`.
- [x] 1.2 Дельта спецификации `claude-input`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `openspec validate claude-input-focus --strict`.

## 3. Проверка вживую (агент)

- [x] 3.1 (focused: true у nvim, но клиент переключился на workspace) В своём workspace после старта пробной сессии панель nvim с `focused: true`.
- [ ] 3.2 НЕ ПРОЙДЕНА: `split --focus` и `pane focus` в невидимом workspace переключают клиент; нужна доработка herdr или условный фокус (решение главной сессии).
