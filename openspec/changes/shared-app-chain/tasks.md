## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: `Config::responders` — все записи workspace с ключом, равным цепочке, по порядку раздела; `responds` берёт первую. `keys.rs`: отказ для двух записей одного workspace с одним ключом заменён проверкой одного режима (D3). Проверка: модульные тесты `same_chain_in_one_workspace_shares_cycle`, `override_shares_chain_in_workspace` (одна привязка с двумя источниками, `luac`, клавиша переключателя по-прежнему своя). Выполнено 17.10.2026 (коммит `f09f81f`).
- [x] 1.2 `daemon.rs`: `key_group` (D1), `group_windows`, `cycle_group` вместо цикла одного приложения (prev группы, главное место группы в режиме `swap`, запуск первой записи без окон — D2, D3), `next_app_window` по группе, `AppRoute::with_app` и `--new` у приложения активного окна (D4). Проверка: модульные тесты `shared_chain_group`, `shared_chain_cycle_order`, обновлённые `next_app_follows_config_order`. Выполнено 17.10.2026 (`f09f81f`).
- [x] 1.3 `keys_help.rs`: описание «chrome-ai, chrome-ai2 в workspace surf» (D5); `README.md` демона. Проверка: дополнение теста `sticky_entries_and_section`. Выполнено 17.10.2026 (`f09f81f`).
- [x] 1.4 Сборка и проверки: `cargo test -j 8` — 170 тестов проходят (было 168), `cargo clippy --all-targets` без замечаний, `cargo build --release`. Выполнено 17.10.2026.

## 2. Документация

- [x] 2.1 `docs/window-model.md` (раздел о клавише приложения) и `AGENTS.md` (он же `CLAUDE.md`, абзац о Super+B/V/Y): общая клавиша нескольких приложений workspace. Выполнено 17.10.2026.

## 3. Проверка вживую командами (агент)

- [x] 3.1 Перезапуск службы на новом демоне: `systemctl --user restart workspaced.service`. Проверка: служба активна, в журнале восстановление сессии и «демон запущен» без ошибок; `workspaced check` на действующем конфиге — конфиг корректен; `workspaced keys --list` совпадает с выводом до перезапуска, строка `SUPER+V` — `key SUPER+V` от `workspaces.surf.apps.chrome-ai`. Выполнено 17.10.2026.
- [x] 3.2 Копия действующего конфига во временном `XDG_CONFIG_HOME` с записью `[apps.chrome-ai2]` (команда `true`) и `chrome-ai2 = { cell = "right", chain = "SUPER+V" }` в `surf`. Проверка: `workspaced check` — корректен; `keys --list` — одна строка `SUPER+V` с источниками `workspaces.surf.apps.chrome-ai,workspaces.surf.apps.chrome-ai2`, `SUPER+S r v` и `SUPER+S s v` по одной; `keys --json` — описание «chrome-ai, chrome-ai2 в workspace surf». Живая сессия при этом не менялась. Выполнено 17.10.2026.

## 4. Конфиг и проверка после переезда профиля «AI2»

- [x] 4.1 После переезда профиля «AI2» в каталог `~/.config/google-chrome-ai2` с классом `google-chrome-ai2` добавить в `dot_config/workspaced/config.toml` запись `[apps.chrome-ai2]` и `chrome-ai2 = { cell = "right", chain = "SUPER+V" }` в раздел `surf`, обновить комментарий к `surf`, `chezmoi apply`, `workspaced check`, `workspaced keys --list | rg 'SUPER\+V'`. Выполняет основная сессия. Выполнено 17.10.2026: `[apps.chrome-ai2]` и запись `surf` добавлены (коммит 83304d4), `chain = "SUPER+V"` добавлен основной сессией.
- [x] 4.2 Командами: `workspaced key 'SUPER+V'` по шагам в `surf` при двух окнах у каждого профиля, при окнах только у одного и без окон. Проверка по `hyprctl activewindow -j` и журналу: порядок окон по D1, конец цикла возвращает prev, без окон запускается только `chrome-ai`. Выполнено 17.10.2026 командами со стола 4: первое нажатие подняло `surf` на столе 1 с фокусом на chrome-ai, второе — chrome-ai2, третье закончило цикл и вернуло prev (yandex-browser), четвёртое снова chrome-ai. Вживую проверен только случай по одному окну у каждого профиля; два окна у приложения, окна только у одного и запуск без окон покрыты тестами демона (shared_chain_cycle_order, same_chain_in_one_workspace_shares_cycle).

## 5. Проверка вживую (пользователь)

- [ ] 5.1 Физические клавиши после 4.1: Super+V несколько раз в `surf`. Проверка: окна обоих профилей поднимаются по очереди, после последнего фокус возвращается окну, с которого начали.
- [ ] 5.2 Цепочка с выходом: Super+S, S, V из окна `chrome-ai2`. Проверка: открывается новое окно `chrome-ai2`, а не `chrome-ai`.
