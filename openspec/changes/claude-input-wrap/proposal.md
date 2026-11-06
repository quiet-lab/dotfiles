## Why

Надиктованный текст в панели ввода рядом с Claude Code оказывается длинной
строкой, которая уходит за ширину окна Neovim и не видна целиком. Решение
пользователя 7 ноября 2026: строки переносятся визуально, содержимое буфера
и строка ввода Claude Code не меняются.

## What Changes

- Окна буферов `claude://input` и `claude://dialog` получают `wrap`,
  `linebreak` и `breakindent` при каждом показе буфера; при уходе буфера
  из окна прежние значения возвращаются.
- Новое требование в спецификации `claude-input`.

## Capabilities

### New Capabilities
—

### Modified Capabilities
- `claude-input`: визуальный перенос строк в окне буфера.

## Impact

- `dot_config/nvim/local/claude-input/lua/claude_input/init.lua`,
  `tests/switch_spec.lua`, `docs/claude-input.md`.
