## Why

Neovim в панели ввода иногда зависает и не реагирует на клавиши. Закрыть панель
и открыть её заново вручную долго, а завершать процессы по образцу запрещено.

## What Changes

- Хук `herdr-claude-input.sh` получает режим `reopen`: закрывает панель буфера
  командой `herdr pane close`, удаляет файл соответствия и проходит тем же
  путём `open`, что и при старте сессии.
- Пользовательский навык `input-reopen` (`dot_claude/skills/input-reopen`)
  вызывает режим `reopen` командой `/input-reopen`.
- Новое требование «Панель буфера переоткрывается командой» в `claude-input`.
- `docs/claude-input.md`: строка о команде.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: переоткрытие панели буфера командой.

## Impact

- `dot_claude/hooks/executable_herdr-claude-input.sh`,
  `dot_claude/skills/input-reopen/SKILL.md`, `docs/claude-input.md`.
- `dot_claude/settings.json` не меняется.
