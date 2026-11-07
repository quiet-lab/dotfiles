## 1. Хук и документ

- [x] 1.1 Хук: `find_claude_pane`, `reopen` без проверки предков.
- [x] 1.2 Дельта спецификации `claude-input`, `design.md`, `docs/claude-input.md`.
- [x] 1.3 `bash -n`, shellcheck, `openspec validate input-reopen-key --strict`.

## 2. Проверка вживую (агент)

- [x] 2.1 `reopen` с панели буфера, с панели Claude и с третьей панели workspace: новая панель на 13 строк, файл и токен указывают на неё.

## 3. Клавиша herdr

- [x] 3.1 Привязка Ctrl+Alt+R в `dot_config/herdr/config.toml`, `reload-config` без диагностики.
- [x] 3.2 Путь клавиши проверен методом `pane run-command` с панели буфера (команда через `/bin/sh -lc`, без предка claude); нажатие проверит пользователь после перезагрузки конфигурации клиента.
