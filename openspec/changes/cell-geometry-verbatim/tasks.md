## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `state.rs`: `rect_for` возвращает ячейку без `inset`; комментарии к `gap` и `inset` в `config.rs`; `cargo test`, `cargo build --release`, перезапуск `workspaced.service`

## 2. Конфиг

- [x] 2.1 `dot_config/workspaced/config.toml`: шапка о смысле ячеек и `gap`; ячейки `halves`, `thirds`, `overlay`, `cross` переписаны на геометрию окон; `chezmoi apply`, `workspaced check`
- [x] 2.2 `workspaced raise work` и `raise surf --desktop 2`: `hyprctl clients -j` показывает окна work −805/1125/3055 по 1920×2140 и окна surf 340/1125/1910 по 1920×2140, ровно как в конфиге

## 3. Спецификации и документация

- [x] 3.1 Дельты ws-daemon и ws-config, `openspec validate cell-geometry-verbatim --strict`
- [x] 3.2 AGENTS.md
