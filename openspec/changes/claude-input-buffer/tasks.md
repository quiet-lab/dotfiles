## 1. Пробы

- [x] 1.1 Пробы П1–П4 на Claude Code 2.1.319 в отдельном workspace herdr; итоги и выбор — в `design.md`.

## 2. Сценарий хука

- [ ] 2.1 `dot_claude/hooks/executable_herdr-claude-input.sh` (`open`, `close`) по D5. Проверка: `bash -n`, `shellcheck`.
- [ ] 2.2 `dot_claude/settings.json`: `SessionStart` (`^(startup|resume)$`) и `SessionEnd`. Проверка: `jq` читает файл, прочие блоки не изменились.

## 3. Плагин neovim

- [ ] 3.1 `dot_config/nvim/local/claude-input/lua/claude_input/init.lua` и `dot_config/nvim/lua/plugins/claude-input.lua` по D1–D4, D6. Проверка: `stylua --check`, загрузка `nvim --headless +ClaudeInput +qa`.

## 4. Документация

- [ ] 4.1 `docs/README.md` — строка о буфере ввода; `AGENTS.md` — упоминание хука.

## 5. Проверка вживую (агент)

- [ ] 5.1 `chezmoi apply --source <worktree>` для файлов задачи; запуск `claude` в отдельном workspace herdr: панель 13 строк, режим вставки, трансляция, замена, `:w` с `/help`, выход закрывает панель, повторный `SessionStart` второй панели не создаёт. Журнал — в каталоге задачи.
