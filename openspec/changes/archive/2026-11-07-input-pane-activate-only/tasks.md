## 1. Хук и спецификация

- [x] 1.1 Хук: снят запасной путь, ошибка в stderr при отсутствии `pane activate`.
- [x] 1.2 Дельта спецификации `claude-input`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `shellcheck`, `openspec validate input-pane-activate-only --strict`.

## 3. Проверка вживую (агент)

- [x] 3.1 Панель nvim открыта, токен `input_pane`, фокус у панели nvim, активный workspace клиента не изменился.
