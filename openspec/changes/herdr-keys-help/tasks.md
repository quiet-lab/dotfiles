Исполнитель указан в скобках: Opus — ядро, формат манифеста и конфигурации,
протокол kitty; Sonnet — манифесты, тесты, документация. Решения — D-номера
`design.md`.

## 1. Каркас плагина и сборка (Opus)

- [ ] 1.1 `dot_config/herdr/plugins/keys-help/`: `herdr-plugin.toml` (D1), `Cargo.toml`, `Cargo.lock`, `src/main.rs` с подкомандами `toggle`, `viewer`, `table`, `unknown list`. Проверка: `cargo build --release --locked`, `cargo clippy` без замечаний.
- [ ] 1.2 Сценарий `run_onchange_after_build-herdr-keys-help.sh.tmpl` (хеш исходников, сборка, `herdr plugin link`), `.chezmoiignore` для каталога `herdr-keys-help/` источника (D12). Проверка: `chezmoi apply`, `herdr plugin list` показывает плагин без `warnings`; повторный `apply` сборку не запускает.

## 2. Ядро (Opus)

- [ ] 2.1 `herdr.rs`: клиент сокета (запросы, подписка `events.subscribe`, `events_lost` → новая подписка и чтение состояния) (D3).
- [ ] 2.2 `channel.rs`: inotify каталога записей, разбор записей, порядок по `mtime`/событиям, pidfd живости и удаление записей умерших процессов, файл `env-vars` (D2).
- [ ] 2.3 `toggle`: поиск просмотрщика по токену, `plugin pane open`/`close` (D4).
- [ ] 2.4 `viewer`: цикл `poll` (подписка, inotify, signalfd, pidfd, ввод), токен, начальная доля `layout.set_split_ratio`, минимум 5 строк по `SIGWINCH`/`layout.updated` через `pane.resize`, следование за фокусом, `pane.moved`, выход (D3, D4).
- [ ] 2.5 `manifest.rs` и `extract/`: формат манифеста, виды источников `regex` (с `sections`, `unquote`, глобальным поиском), `toml`, `json`, `static`, подстановки, нормализация клавиш, `describe`/`group`/`origin`, запуск команд без терминала с ожиданием по pidfd и завершением при смене контекста, кеш в памяти (D6).
- [ ] 2.6 `context.rs`: разрешение контекста по записям, процессам, заголовку, экрану, подписки `pane.output_matched` из манифестов (D5).
- [ ] 2.7 `view.rs`: слияние конфигурации, шаблоны, фильтрация, порядок, `[entry]`, перечитывание по inotify; запись `d`/`D`/`u` через `toml_edit` с `rename` по настоящему пути (D12).
- [ ] 2.8 `ui.rs`: шапка, группы колонками, подписи происхождения, выбор, клавиши `j`/`k`/`d`/`D`/`u`/`q` (D13).
- [ ] 2.9 Универсальный извлекатель как механизм `generic.toml` (`fallback`, кеш на диске по входам) и `unknown.rs` (файл неизвестных, `flock` с комментарием о ресурсе) (D7, D8).

## 3. Поставщики (Opus — ble.sh; Sonnet — Neovim)

- [ ] 3.1 `dot_config/blesh/keys-help.bash` и строка подключения в `dot_blerc` (D10). (Opus)
- [ ] 3.2 `dot_config/nvim/lua/keys_help.lua`, вызов `setup()` из `lua/config/autocmds.lua` (D11). (Sonnet)

## 4. Манифесты первой очереди (Sonnet)

- [ ] 4.1 `ble.toml`: режимы, регулярное выражение дампа `-P`, описания виджетов по-русски, группы (`history`, `completion`, `edit`, `motion`, …), происхождение (`readline`, `ble`, `fzf`, `atuin`, `tv`, `user`).
- [ ] 4.2 `fzf.toml` (man fzf + `{env.FZF_DEFAULT_OPTS}`), `atuin.toml` (`keymap_mode`, `[keys]`), `tv.toml` (`[keybindings]`).
- [ ] 4.3 `yazi.toml` и `manifests/data/yazi-keymap-26.9.1.toml` (умолчания yazi 26.9.1 из исходников выпуска), имена слоёв.
- [ ] 4.4 `nvim.toml` (источник `json` через `--remote-expr`, статическая таблица базовых клавиш vim в `manifests/data/`).
- [ ] 4.5 `generic.toml`: заголовки разделов man, признаки клавиш, шаблоны файлов конфигурации.

## 5. Открытые вопросы

- [ ] 5.1 Координатор: ответ пользователя о слое yazi (D9); записать выбранный вариант в `design.md` D9 и в «Переданные».
- [ ] 5.2 Координатор: подтверждение доли нижней панели (литерал `--ratio 0.333` против семантики herdr, `design.md`, Context).
- [ ] 5.3 Поставщик yazi по ответу 5.1 (вариант без правки `init.lua` — только манифест; иначе — модуль под chezmoi). (Sonnet)

## 6. Автоматические тесты (Sonnet)

- [ ] 6.1 Слияние конфигурации: уровни, шаблоны `x.*` и `*.generic`, объединение `hide`/`hide_groups`, замена прочих полей, `[entry]`; пример решения 6.
- [ ] 6.2 Фильтрация и порядок: `hide`, `hide_groups`, `pin`, `order`, `only_modifiers`, `show_origin`.
- [ ] 6.3 Запись `d`/`D`/`u`: комментарии сохранены, новый раздел создаётся, символическая ссылка остаётся ссылкой.
- [ ] 6.4 Разбор манифестов: все манифесты `manifests/` разбираются; ошибочный пропускается с сообщением; тестовый манифест `kh-fake` распознаётся без правки ядра.
- [ ] 6.5 Извлечение: фикстура `ble-bind -P` (снята с живого ble.sh), `keymap.toml` yazi с `prepend_keymap`, `[keybindings]` tv, `--bind` fzf, раздел `KEY BINDINGS` man-фикстуры, нормализация клавиш.
- [ ] 6.6 Канал: порядок записей, стек bash → yazi → nvim, удаление записи умершего процесса по pidfd (тестовые процессы с `HERDR_PANE_ID` из временного каталога).
- [ ] 6.7 Файл неизвестных программ: счётчик, дата, без повторов, удаление при появлении таблицы; кеш универсального извлекателя не повторяет запуск при тех же входах.
- [ ] 6.8 Модуль ble.sh на живом ble.sh под псевдотерминалом (`script`): записи при смене keymap, `exec`, `widget`, `PRECMD`, дамп `-P`, отсутствие внешних процессов на смену keymap.
- [ ] 6.9 Модуль Neovim: `nvim --headless` с `HERDR_PANE_ID` — записи `ModeChanged`, удаление на выходе, `dump()` возвращает JSON с `desc`.

## 7. Конфиг herdr и wezterm

- [ ] 7.1 `dot_config/herdr/config.toml`: `[[keys.command]]` клавиши `ctrl+alt+shift+slash` → `quiet-lab.keys-help.toggle`; `[ui]` `pane_outer_borders = false`, `pane_gaps = false` (D14). Проверка: `herdr server reload-config` без диагностик. (Sonnet)
- [ ] 7.2 `enable_kitty_keyboard = true` в `dot_config/wezterm/wezterm.lua` и таблица регрессий решения 2 — результат параллельного исполнителя; здесь отметить ссылкой на его отчёт. (Opus, отдельный исполнитель)
- [ ] 7.3 Если клавиша не доходит до herdr после 7.2 — доработка форка herdr по решению 2 (`docs/duty/README.md` форка). (Opus)

## 8. Проверка вживую командами (агент)

- [ ] 8.1 Открытие и закрытие: `herdr plugin action invoke quiet-lab.keys-help.toggle`, `herdr pane list` до и после, высота ≈ 1/3 и ≥ 5 строк, повторный вызов закрывает.
- [ ] 8.2 Контексты ble.sh: `herdr pane send-keys` Esc и `i` в оболочку панели, после каждого события — `herdr pane read <просмотрщик> --source visible` показывает `ble.vi_nmap`/`ble.vi_imap`.
- [ ] 8.3 Запуск и выход yazi, atuin, fzf, tv, Neovim командами `pane run`/`send-keys`; после каждого — чтение панели просмотрщика.
- [ ] 8.4 Следование за фокусом: `herdr pane focus` другой панели workspace — шапка показывает её `pane_id`.
- [ ] 8.5 Неизвестная программа: запуск `kh-unknown` — строка в файле неизвестных; хук `SessionStart` печатает её.
- [ ] 8.6 Скрытие: `pane send-keys` `d` в панель просмотрщика — запись в `view.toml` источника, запись исчезла из панели.

## 9. Проверка вживую (пользователь, по одному вопросу)

- [ ] 9.1 Физическое нажатие Ctrl+Alt+Shift+/ открывает и закрывает панель.
- [ ] 9.2 Вид рамок herdr (разделители без внешних рамок и промежутков).
- [ ] 9.3 Клавиши, которые нельзя подать командой (M-f, M-r, M-t в оболочке), — таблица fzf/atuin/tv в панели.

## 10. Хук разбора и документация (Sonnet)

- [ ] 10.1 `.claude/hooks/keys-help-unknown.sh` и запись `SessionStart` в `.claude/settings.json` (D8).
- [ ] 10.2 `docs/keys-help.md`: устройство, канал, контексты, формат манифеста и конфигурации представления, добавление программы, универсальный извлекатель, файл неизвестных программ и порядок разбора.
- [ ] 10.3 Строка в `docs/README.md`, абзац в `CLAUDE.md` проекта (клавиша, плагин, ссылка на `docs/keys-help.md`).
- [ ] 10.4 Запись в `docs/decisions/` по README каталога (Y-statement): плагин herdr с панелью split вместо панели Quickshell или вывода в инфо-области ble.sh, протокол kitty в wezterm, рамки herdr только разделителями.

## 11. Завершение (координатор)

- [ ] 11.1 Ревью по порядку `~/.claude/CLAUDE.md`, «Субагенты»; `openspec validate herdr-keys-help --strict`; `openspec archive herdr-keys-help -y` после живой проверки.
