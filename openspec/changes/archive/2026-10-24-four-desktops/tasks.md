## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: ключ `desktops`, `MAX_DESKTOPS`, `desktop_count`, `is_desktop`, `check_desktop`; проверки `[startup]`, `desktop` в действиях, серии `range` с `move` (D1). `keys.rs`: номер стола `move` по N. `daemon.rs`: событие смены стола, `sync_current`, `move_desktop`, `state_json`, проверка стола в `handle_request`. `hypr.rs`: `Client::desktop` по `MAX_DESKTOPS`. `main.rs`: «столов: N» в сводке `check`.
- [x] 1.2 `session.rs`: `limit_desktops` и `read_for_load` для `restore_default` и `load` (D2).
- [x] 1.3 Тесты `desktops_key_limits_desktop_numbers`, `snapshot_desktops_beyond_limit_are_dropped`; `CARGO_BUILD_JOBS=16 cargo test -- --test-threads=8` — 184 теста проходят, `cargo clippy --all-targets` без замечаний, `cargo build --release`. `README.md`: раздел «Столы», `move-desktop`, формат снимка.
- [x] 1.4 Коммит и push демона.

## 2. Конфиг сессии

- [x] 2.1 `systemctl --user restart workspaced.service` на новом бинарнике, затем `desktops = 4` и `range = [1, 4]` у Super+$n, Shift+Super+$n, Ctrl+Super+$n в `dot_config/workspaced/config.toml`; `chezmoi apply ~/.config/workspaced/config.toml`, `workspaced check` — «столов: 4», демон перечитал конфиг.
- [x] 2.2 `dot_config/hypr/hyprland.lua`: постоянные столы 1…4; `hyprctl reload config-only` — обычные столы «1»…«4», ошибок конфига нет.

## 3. Панель

- [x] 3.1 `tiles/Workspaces.qml`: плитки по столам состояния демона (D3), все 274×82 с шагом 92 px, табы во всех плитках, без «+k» и иконок workspace в ряду, без анимации (D4); IPC `desktops`. `shell.qml`: координаты (D5). `tiles/Tray.qml`: высота 266.
- [x] 3.2 `chezmoi apply ~/.config/quickshell`; в `qs log -c panel` «Reloading configuration...» и «Configuration Loaded» без ошибок QML; `qs -c panel ipc call workspaces desktops` — `[1,2,3,4]`, `row 1…4` отдают ряды окон.

## 4. Спецификации и документация

- [x] 4.1 Дельты ws-config, ws-daemon, ws-sessions, hyprland-binds, hyprland-config, qs-shell, qs-tray-lang, qs-notifications, qs-workspaces; дельты `chains-sticky`, `sticky-chains`, `toggle-windows`, `work-area-center`, `live-layout` (D6). `openspec validate --strict` для всех активных изменений, `openspec validate --specs`.
- [x] 4.2 `AGENTS.md` (он же `CLAUDE.md`), `docs/window-model.md`, `todo.md`.

## 5. Проверка вживую (пользователь)

- [x] 5.1 Вид колонки: четыре плитки столов одной высоты с табами на 1462…1820 px, жёлтый блок номера только у активного стола, правая колонка (уведомления, трей, раскладка) вровень с блоком, средняя группа по центру между погодой и столами; клавиши Super+1…4 и Ctrl+Super+1…4.

## 6. Архивация

- [x] 6.1 Поправить `## Purpose` спецификации qs-workspaces (раздел «Risks» в `design.md`), `openspec archive four-desktops -y`, `openspec validate --specs`.
