## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `src/hypr.rs`: поля `allowed_over_fullscreen` и `pinned` у `Client`, диспетчер `d_lower`, расчёт `d_cover_fullscreen` (D1); тест `cover_fullscreen_lowers_windows_over_it`.
- [x] 1.2 `src/daemon.rs`: `cover_fullscreen` после команд `raise`, `app`, `key`, `next`, `move-desktop`, в том числе после ошибки команды (D1).
- [x] 1.3 `cargo test` — 185 тестов проходят, `cargo clippy --all-targets -- -D warnings` без замечаний, `cargo build --release`, перезапуск `workspaced.service`, `workspaced check`.
- [x] 1.4 Коммит и push демона.

## 2. Проверка вживую

- [x] 2.1 Агент: в `surf` с Яндекс.Браузером в полноэкранном режиме `workspaced key 'Super+B'` — Chrome в фокусе и виден поверх видео (`allowedOverFullscreen` у Chrome), `workspaced key 'Super+Y'` — Яндекс.Браузер виден поверх, у Chrome признак снят, `fullscreen` и `fullscreenClient` Яндекс.Браузера остались 2; поднятие `surf` клавишей Super+Y с другого workspace стола — то же; снимки экрана `grim`.
- [x] 2.2 Проверка пользователем нажатиями (Super+B и Super+Y в `surf` при полноэкранном видео в Яндекс.Браузере) перенесена в `todo.md`.

## 3. Спецификации и документация

- [x] 3.1 Дельта ws-daemon, `openspec validate fullscreen-raise --strict`.
- [x] 3.2 `docs/window-model.md`, `AGENTS.md` (он же `CLAUDE.md`).
- [x] 3.3 Архивация, `openspec validate --specs`.
