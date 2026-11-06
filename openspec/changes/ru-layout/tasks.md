## 1. Таблица

- [x] 1.1 `table.lua` и `gen-table.lua` из `dot_config/X11/xkb_custom`, `tr.lua`. Проверка: `tests/table_spec.lua`, `tests/tr_spec.lua`.

## 2. Раскладка

- [x] 2.1 `layout.lua`: раскладка из Hyprland по событиям, переподключение по inotify, работа без Hyprland. Проверка: `tests/layout_spec.lua` на двойнике `fake-hypr.py`.

## 3. Привязки

- [x] 3.1 `langmap` из таблицы и `keymap.lua` по D1. Проверка: `tests/keymap_spec.lua`.

## 4. Знаки, `r`, `@`

- [x] 4.1 `punct.lua`, `macro.lua`, `rchar.lua` по D4, D8. Проверка: `tests/punct_spec.lua`, `tests/macro_spec.lua`, `tests/rchar_spec.lua`.

## 5. Командная строка и диалоги

- [x] 5.1 `cmdline.lua` по D3 и `<M-l>` в `/`, `dialogs.lua` по D8. Проверка: `tests/cmdline_spec.lua`, `tests/dialogs_spec.lua`; тесты `claude-input` зелёные.

## 6. flash

- [x] 6.1 `flash.lua` по D5. Проверка: `tests/flash_spec.lua`.

## 7. Плагины

- [x] 7.1 `getchar.lua`, `plugins.lua` по D6 и сторожевой тест. Проверка: `tests/getchar_spec.lua`, `tests/plugins_spec.lua`, `tests/guard_spec.lua`.

## 8. Терминал

- [x] 8.1 `terminal.lua` по D9. Проверка: `tests/terminal_spec.lua`.

## 9. Подключение

- [x] 9.1 `init.lua`, `lua/plugins/ru-layout.lua`, подмена API до `lazy.setup` в `lua/config/lazy.lua`. Проверка: `tests/smoke_spec.lua`, `tests/run-all.sh`, `nvim --headless "+lua require('ru-layout')" +q`.

## 10. Документация

- [x] 10.1 `docs/ru-layout.md`, строка в `docs/README.md`, абзац в `AGENTS.md`.

## 11. Проверка вживую (пользователь)

- [x] 11.1 Событие `activelayout` Hyprland при Super+Пробел и приход Alt+`в` как `<M-d>`. Передано главной сессии: проверку выполняет пользователь, сценарии описаны в `docs/ru-layout.md`.
