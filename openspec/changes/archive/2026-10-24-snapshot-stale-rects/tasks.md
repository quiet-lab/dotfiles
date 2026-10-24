## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `src/state.rs`: таблица `grid` у `SessionWorkspace` (D2).
- [x] 1.2 `src/session.rs`: `template_grid`, `stale_layout` вместо `stale_cell`, `forget_stale_layouts` в `read_for_load`, геометрия ячеек в `session_workspaces` (D1, D2); тесты `stale_snapshot_cell_is_found`, `stale_layout_drops_window_rects`, проверка `grid` в `snapshot_writes_layout`.
- [x] 1.3 `cargo test` — 186 тестов проходят, `cargo clippy --all-targets -- -D warnings` без замечаний, `cargo build --release`, перезапуск `workspaced.service`, `workspaced check`.
- [x] 1.4 Коммит и push демона.

## 2. Проверка вживую

- [x] 2.1 Агент: перезапуск демона со снимком, записанным по шаблону `thirds`, — в журнале раскладка `work` собирается заново из конфига, прямоугольники окон для `work` из снимка не действуют; `workspaced status --json` показывает назначения `thirds-split` (`chromium` — `left_top`, `chrome` — `left_bottom`, `herdr` — `center`, `neovide` — `right`), окна стола 1 не перезапущены и не сдвинуты.
- [x] 2.2 Проверка перезагрузкой (окна `work` после перезагрузки встают по `thirds-split`) перенесена в отчёт пользователю.

## 3. Спецификации и документация

- [x] 3.1 Дельта ws-sessions, `openspec validate snapshot-stale-rects --strict`.
- [x] 3.2 `docs/window-model.md`, `AGENTS.md` (он же `CLAUDE.md`).
- [x] 3.3 Архивация, `openspec validate --specs`.
