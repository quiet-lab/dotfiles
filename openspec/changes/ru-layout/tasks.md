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

- [x] 11.1 Событие `activelayout` Hyprland при Super+Пробел и приход Alt+`в` как `<M-d>`. Проверено главной сессией через ydotool: activelayout на каждое переключение; wezterm — `<M-d>`/`<C-d>`, Neovide — `<M-в>`/`<C-в>`; обе формы покрыты задачей host-keys.

## 12. Независимость от хоста

- [x] 12.1 `chords.lua` (алиасы, чтецы, явные сочетания), перечень `index.lua` и генератор `gen-index.lua` из `index.txt`, две формы дубля и обратный дубль в `keymap.lua`, перевод сочетаний в `getchar.lua` по D10. Проверка: `tests/chords_spec.lua`, `tests/run-all.sh`, тесты `claude-input`.
- [x] 12.2 Раздел о независимости от хоста и живые проверки в `docs/ru-layout.md`, требование «Поведение не зависит от хоста».
- [x] 12.3 Живая проверка в wezterm и Neovide нажатиями ydotool (сценарий `live-check/run.py` задачи host-keys): insert Ctrl+ц, Ctrl+к ф, normal Ctrl+ц ы, терминал Ctrl+ф и Alt+в, `:` Ctrl+к ф — одинаковый итог в обоих хостах; прежний модуль в Neovide даёт 6 расхождений из 6.
