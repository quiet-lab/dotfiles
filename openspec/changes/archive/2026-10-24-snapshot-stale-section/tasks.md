## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `src/state.rs`: поля `homes` и `homes_main` у `SessionWorkspace` (D1).
- [x] 1.2 `src/session.rs`: дома раздела в `session_workspaces`, `stale_section` в `stale_layout`, очистка в `forget_stale_layouts` (D2, D3); тест `stale_section_is_found`, поправка `stale_snapshot_cell_is_found`.
- [x] 1.3 `src/daemon.rs`: `missing_homes` в `rebuild_cfg` (D4), тест `missing_homes_fill_collected_layout`.
- [x] 1.4 `cargo test` — 188 тестов проходят, `cargo clippy --all-targets -- -D warnings` без замечаний, `cargo build --release`, перезапуск `workspaced.service`, `workspaced check`.
- [x] 1.5 Коммит и push демона.

## 2. Проверка вживую

- [x] 2.1 Агент: перезапуск демона со снимком, где в раскладке `surf` нет `chrome-ai2`, — в журнале раскладка `surf` собирается заново из конфига; после поднятия `surf` окно `chrome-ai` стоит в `left` (340,10 1920×2140), `chrome-ai2` — в `right` (1910,10 1920×2140); цикл Super+V выбирает `chrome-ai`, затем `chrome-ai2` поверх с фокусом, затем возвращает Яндекс.Браузер; окна `work` после возврата на месте.
- [x] 2.2 Проверка нажатиями Super+V перенесена в отчёт пользователю.

## 3. Спецификации и документация

- [x] 3.1 Дельта ws-sessions, `openspec validate snapshot-stale-section --strict`.
- [x] 3.2 `docs/window-model.md`, `AGENTS.md` (он же `CLAUDE.md`).
- [x] 3.3 Архивация, `openspec validate --specs`.
