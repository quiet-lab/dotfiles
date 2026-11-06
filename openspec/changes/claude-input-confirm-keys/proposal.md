## Why

Подтверждать выбор в диалоге приходится командой `:w`. Решение пользователя
7 ноября 2026: Shift+Enter и Shift+Пробел в буфере диалога подтверждают
выделенный пункт, как `:w`.

## What Changes

- В буфере `claude://dialog` привязки `<S-CR>` и `<S-Space>` (режимы вставки
  и обычный) вызывают ту же функцию подтверждения, что `:w`.
- В буфере `claude://input` эти клавиши не привязываются.
- Требование «Сохранение буфера диалога подтверждает выбор» дополняется.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: подтверждение выбора клавишами Shift+Enter и Shift+Пробел.

## Impact

- `dot_config/nvim/local/claude-input/lua/claude_input/init.lua`,
  `tests/switch_spec.lua`, `docs/claude-input.md`.
