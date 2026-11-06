## 1. Хук и спецификация

- [x] 1.1 Убрать проверку `DUTY_TASK` из хука и комментарий об исключении.
- [x] 1.2 Дельта спецификации `claude-input`, `docs/claude-input.md`.

## 2. Проверка

- [x] 2.1 `bash -n`, `shellcheck`, `openspec validate claude-input-workers --strict`.

## 3. Проверка вживую (агент)

- [ ] 3.1 Пробная панель с `DUTY_TASK`: панель nvim на 13 строк появляется и закрывается хуком `close`. Журнал — каталог задачи.
