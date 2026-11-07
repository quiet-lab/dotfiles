## Why

Буфер ввода `claude://input` не даёт вернуться к прежним запросам: в самом
Claude Code стрелки вверх и вниз листают историю ввода, а в буфере neovim они
лишь двигают курсор.

## What Changes

- `<Up>` на первой строке буфера ввода и `<Down>` на последней листают историю
  запросов проекта из `~/.claude/history.jsonl`; черновик сохраняется.
- Файл читается по требованию при первом `<Up>` после сброса, без наблюдателей
  и таймеров.
- Добавляется требование «История ввода в буфере ввода»; `docs/claude-input.md`.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: листание истории ввода стрелками в буфере ввода.

## Impact

- `dot_config/nvim/local/claude-input` (код и `tests/switch_spec.lua`), `docs/claude-input.md`.
