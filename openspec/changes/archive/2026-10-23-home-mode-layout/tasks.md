## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: `Mode::Home`, `MODES` с `home` (сообщение об ошибке перечисляет `swap`, `stack`, `home`), `Mode::takes_main`, ячейки шаблона в порядке файла (`IndexMap`, D3, D8). Проверка: тесты `workspace_mode_and_app_order`, `template_cells_keep_file_order`, `ws_app_entry_errors`.
- [x] 1.2 `state.rs`: `home_places`, `home_place`, `config_main`, `home_layout` (D1–D3), сборка раскладки workspace режима `home` в `State::cells_of` (D5), `State::moved_applies` и `State::at_home` в `rect_for` (D4).
- [x] 1.3 `daemon.rs`: `home_to_main_plan`, `Daemon::home_to_main`, `Daemon::take_main` в цикле, запуске, выборе окна и новом экземпляре (D1); снятие раскладки не трогает изменённое место вне дома (D4). `save.rs`: `record_place`, `mode = "home"` (D6). `hypr.rs`: `d_place` задаёт размер и положение дважды (D9). `session.rs`: `stale_cell` (D10). `README.md` демона.
- [x] 1.4 Тесты: `home_mode_user_example_full` (три шага примера), `home_mode_without_chrome_prefers_freed_cell`, `home_mode_end_of_cycle_restores_homes`, `home_mode_stacks_several_windows`, `home_mode_displaced_without_free_cell` (в том числе дом-прямоугольник записи сессии), `home_mode_moved_rect_only_at_home`, `home_mode_initial_layout_and_arrange`, `home_mode_save_writes_homes`, `stale_snapshot_cell_is_found`. `CARGO_BUILD_JOBS=16 cargo test -- --test-threads=8` — 181 тест проходит, `cargo clippy --all-targets` без замечаний, `cargo build --release`. Коммит демона `41abe4d`.

## 2. Спецификации, конфиг и документация

- [x] 2.1 Дельты ws-daemon («Цепочка приложения», «Расстановка окон», «Возврат раскладки к конфигу по команде») и ws-config («Файл конфига и его разделы»); дельты этих требований в `live-layout`, `work-area-center`, `shared-app-chain` сняты, их `proposal.md`, `design.md`, `tasks.md` отмечают перенос (D11). Проверка: `openspec validate --strict` для всех четырёх изменений.
- [x] 2.2 `dot_config/workspaced/config.toml`: шаблон `thirds-split` с комментарием о геометрии, раздел `work` (`template = "thirds-split"`, `mode = "home"`, `main = "herdr"`, herdr — `center`, chromium — `left_top`, chrome — `left_bottom`, neovide — `right`), комментарий над `surf`. `chezmoi apply ~/.config/workspaced/config.toml`, `workspaced check` — после перезапуска службы на новом бинарнике.
- [x] 2.3 `docs/window-model.md` (разделы 2.1, 2.3, 2.4, таблицы требований, раздел 5), `AGENTS.md` (он же `CLAUDE.md`), `todo.md`.

## 3. Проверка вживую командами (агент)

- [x] 3.1 `systemctl --user restart workspaced.service`; снимок `default` называл ячейку `left` старого шаблона — раскладка `work` собрана из конфига (D10). `workspaced arrange`: `cells` — herdr `center`, chromium `left_top`, chrome `left_bottom`, neovide `right`, `main` herdr, `moved` пуст; окна: herdr 1125,10 1920×2140, chromium -805,10 1920×1065, chrome -805,1085 1920×1065, neovide 3055,10 1920×2140.
- [x] 3.2 `workspaced key 'SUPER+C'`: `main` chromium, chromium `center` (1125,10 1920×2140), herdr `left_top` (-805,10 1920×1065), chrome и neovide не двигались. `workspaced key 'SUPER+SHIFT+B'`: `main` chrome, chrome `center`, chromium `left_top`, herdr `left_bottom` (-805,1085 1920×1065), neovide `right`. `workspaced key 'SUPER+W'`: `main` herdr, всё по домам. `moved` пуст на каждом шаге, размеры окон ровно по ячейкам.
- [x] 3.3 Конец цикла: Super+C дважды — chromium в `center`, затем herdr в `center`, chromium в `left_top`, фокус у herdr. Super+E — neovide в `center`, herdr в освобождённой `right`; `workspaced arrange` — раскладка из файла, `main` herdr. Фокус возвращён окну herdr, активному до проверки; в журнале службы ошибок и предупреждений нет.

## 4. Проверка вживую (пользователь)

Нет: всё проверяемое без физических нажатий проверено командами, привязки Super+C, Shift+Super+B, Super+W вызывают те же команды `workspaced key`.
