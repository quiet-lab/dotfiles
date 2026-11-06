## 1. Пробы

- [x] 1.1 Пробы П1–П4 на Claude Code 2.1.319 в отдельном workspace herdr; итоги и выбор — в `design.md`.

## 2. Сценарий хука

- [x] 2.1 `dot_claude/hooks/executable_herdr-claude-input.sh` (`open`, `close`) по D5. Проверка: `bash -n`, `shellcheck`.
- [x] 2.2 `dot_claude/settings.json`: `SessionStart` (`^(startup|resume)$`) и `SessionEnd`. Проверка: `jq` читает файл, прочие блоки не изменились.

## 3. Плагин neovim

- [x] 3.1 `dot_config/nvim/local/claude-input/lua/claude_input/init.lua` и `dot_config/nvim/lua/plugins/claude-input.lua` по D1–D4, D6. Проверка: `stylua --check`, загрузка `nvim --headless +ClaudeInput +qa`.

## 4. Документация

- [x] 4.1 `docs/claude-input.md` — устройство и проверка после обновления Claude Code; `docs/README.md` — строка указателя. `AGENTS.md` не меняется: сведения нужны не в каждой сессии.

## 5. Проверка вживую (агент)

- [x] 5.1 `chezmoi apply --source <worktree>` для файлов задачи; запуск `claude` в отдельном workspace herdr: панель 13 строк без фокуса, режим вставки, трансляция двух строк, замена после правки, `:w` с `/help` (справка открыта, буфер пуст, без признака изменения), `:q` и выход из Claude Code закрывают панель, повторный `SessionStart` второй панели не создаёт. Журнал — `probe/live.log` каталога задачи.
- [x] 5.2 Отложенная отправка при `blocked` и `:w` при `blocked` — на поддельном сервере herdr (`tests/fake_herdr.py`, `tests/deferred_spec.lua` каталога задачи): 6 проверок из 6.

## 6. Проверка вживую (пользователь)

- [x] 6.1 Набор в панели буфера с клавиатуры: текст повторяется в строке ввода Claude Code, `:w` отправляет запрос, вид панели в 13 строк удобен. Перенесено в `todo.md` (открытые вопросы к пользователю).
