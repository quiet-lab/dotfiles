## Why

Подсказка диалога виртуальными строками занимает 4–7 строк панели ввода высотой 13 строк и отнимает место у текста ответа.

## What Changes

- Подсказка диалога в `claude-input` — плавающее окно в правом нижнем углу окна буфера диалога вместо виртуальных строк; содержимое и обработка клавиш прежние.

## Capabilities

### Modified Capabilities
- `claude-input`: требование «Подсказка в буфере диалога».

## Impact

`dot_config/nvim/local/claude-input` (код и `tests/switch_spec.lua`), `docs/claude-input.md`.
