## 1. Демон workspaced

- [ ] 1.1 `src/config.rs`: раздел `sticky` — `IndexMap<String, StickyChain>` (порядок файла), состояние с полями `title`, `apps`, `keys` (`IndexMap`, клавиша: `state`, `action`, `exec`, `dispatch`, `lua`, `exit`, `desc`), `states` (рекурсивно), `enter` у корня; поле `new` у `TargetAction`; раздел не даёт предупреждения о неизвестном ключе (решение D1)
- [ ] 1.2 `src/keys.rs`: проверка цепочек с выходом — имена, клавиши без `+`, запрет `Escape`/`BackSpace`/мыши, ровно одно действие или дополнение унаследованной клавиши, `exit` без `state`, переход только в дочернее состояние, достижимость состояний, `apps` из `raise`/`spawn`; `enter` — одно звено в общей проверке совпадения, начала цепочки и `reserved` с источником `sticky.<имя>`; ключ `new` только с `app` без `workspace` и `pull` (решения D2, D3, D5, D8)
- [ ] 1.3 `src/keys.rs`: наследование клавиш приложений — цепочки клавиш приложений из одного сочетания с модификатором ровно Super, клавиша в нижнем регистре, действие `workspaced key '<цепочка>'` или `workspaced key --new '<цепочка>'`; явная запись дополняет или заменяет (решения D5, D6)
- [ ] 1.4 `src/keys.rs`, `to_lua`: прямая привязка входа, `hl.define_submap("ws-sticky:<путь>", …)` на каждое состояние, клавиши с `ignore_mods = true`, действие без закрытия подкарты, с `exit` — с закрытием, `BackSpace` к родителю (в корне — закрытие), `Escape`, последней — `catchall` с `hl.dsp.no_op()`; в конце кода — закрытие устаревшей подкарты `ws:`/`ws-sticky:` (решения D4, D9)
- [ ] 1.5 `src/keys.rs`, `to_list`: строки путей `sticky <имя>`, `state <состояние>`, клавиши с действием, флаг `exit`, источник `sticky.<имя>[.<состояние>…]`; пути не участвуют в проверке цепочек (решение D10)
- [ ] 1.6 `src/keys_help.rs`: группа «Цепочки с выходом» после «Приложения», описания путей и клавиш с « · » и « (выход)», раздел `sticky` в JSON (решение D10)
- [ ] 1.7 `src/main.rs`, `src/daemon.rs`: ключ `--new` у `key` и `app`, поле `new` запроса сокета; `Daemon::key`/`Daemon::app` с `new` — по пути `AppRoute` новый экземпляр вместо цикла (в режиме обмена мест — сначала главное место), `Daemon::spawn` с признаком «новый»: отдельная запись ожидания без проверки незавершённого запуска (решения D6, D7)
- [ ] 1.8 Тесты: разбор раздела и каждая ошибка проверки из сценариев ws-config; наследование и дополнение клавиш; код Lua (подкарты, `ignore_mods`, `catchall` последним, `BackSpace` корня и вложенного состояния, закрытие устаревшей подкарты) с проверкой синтаксиса `luac`; строки `--list` и `--json`; `key_route` с `new` для четырёх путей; два ожидания одного приложения и порядок захвата окон
- [ ] 1.9 `cargo test`, `cargo clippy --all-targets -- -D warnings`, `cargo build --release`; `README.md` демона — раздел о цепочках с выходом и ключе `--new`; коммит и push в репозитории демона

## 2. Конфиг демона

- [ ] 2.1 `dot_config/workspaced/config.toml`: раздел `[sticky.apps]` на `SUPER+A` с состояниями `raise` и `spawn` и клавишей `e = { exit = true }` в обоих, комментарий о смысле раздела и о том, почему не Super+S (решение D8)
- [ ] 2.2 `chezmoi apply ~/.config/workspaced/config.toml`; `workspaced check` проходит; журнал демона: конфиг перечитан, `hyprctl reload config-only` выполнен

## 3. Панель Quickshell

- [ ] 3.1 `KeyChains.qml` (синглтон): подписка на `Hyprland.rawEvent` с именем `submap`, начальное чтение `hyprctl submap`, загрузка `workspaced keys --json` при входе в цепочку (разбор по трём событиям процесса, как в `KeysHelp.qml`), текущее состояние из раздела `sticky`, запасной путь из имени подкарты, IPC-цель `chains` с функцией `state` (решение D11)
- [ ] 3.2 `KeyChainsWindow.qml`: окно layer-shell на слое Overlay, без клавиатуры, с пустой маской ввода, карточка в оформлении плиток (`Theme`, `Tile`) вверху по центру рабочей области: путь, строки клавиш, пометка выхода, нижняя строка; ширина по содержимому
- [ ] 3.3 `shell.qml`, `qmldir`; `chezmoi apply` файлов панели, перезапуск `quickshell-panel.service`, журнал без ошибок QML

## 4. Проверка командами (агент)

- [ ] 4.1 `workspaced keys --list`: строки `SUPER+A`, `SUPER+A r`, `SUPER+A r v` — `key SUPER+V`, `SUPER+A s v` — `key --new SUPER+V`, `SUPER+A r e` и `SUPER+A s e` с флагом `exit`; `workspaced keys --json`: группа «Цепочки с выходом» после «Приложения», раздел `sticky` с тремя состояниями
- [ ] 4.2 `workspaced keys --lua | luac -p -`; `hyprctl binds -j`: подкарты `ws-sticky:apps`, `ws-sticky:apps/raise`, `ws-sticky:apps/spawn`, в каждой `BackSpace`, `Escape` и одна привязка `catch_all: true`, у клавиш состояний `ignore_mods`; в `ws:SUPER + TAB` привязки `catch_all` нет
- [ ] 4.3 Проверки отказов `workspaced check` на копии конфига в каталоге `XDG_CONFIG_HOME=<временный каталог>` (рабочий конфиг не трогается): вход `SUPER+S`, вход из `reserved`, клавиша `Escape`, клавиша `SHIFT+v`, переход в чужое состояние, недостижимое состояние, дополнение неунаследованной клавиши, `{ workspace = "work", new = true }`
- [ ] 4.4 Событие `submap`: запись `.socket2.sock` экземпляра Hyprland, затем `hyprctl eval 'hl.dispatch(hl.dsp.submap("ws-sticky:apps"))'`, то же для `ws-sticky:apps/raise`, затем `submap("reset")`: в записи `submap>>ws-sticky:apps`, `submap>>ws-sticky:apps/raise`, `submap>>`; после каждого шага `qs -c panel ipc call chains state` по сценарию qs-key-chains, слой индикатора в `hyprctl layers` только пока карточка показана
- [ ] 4.5 Устаревшая подкарта: открыть `ws-sticky:apps/raise` через `hyprctl eval`, убрать состояние `raise` из конфига, дождаться перечитывания по журналу демона — `hyprctl submap` печатает `default`; вернуть конфиг `chezmoi apply --force ~/.config/workspaced/config.toml`
- [ ] 4.6 Перезапуск панели при открытой подкарте `ws-sticky:apps/spawn`: `chains state` начинается с «shown ws-sticky:apps/spawn»; затем `submap("reset")`
- [ ] 4.7 `workspaced key --new 'SUPER+V'` трижды при активном `surf`: три новых окна с тегами `app:chrome-ai#N`, место `chrome-ai`, последнее в фокусе (`hyprctl clients -j`); `workspaced key --new 'SUPER+E'` на столе с `work`: neovide на главном месте, новое окно в центральной ячейке; `workspaced app neovide --new` на пустом столе — окно в центре рабочей области; лишние окна закрыть

## 5. Проверка пользователем (нажатия)

- [ ] 5.1 Сценарий «Поднять и перейти к открытию» (hyprland-binds, «Цепочка приложений с выходом»): Super+A, R, V, Y, Backspace, S, V, V, E; индикатор показывает путь и клавиши на каждом шаге
- [ ] 5.2 Super не отпущен после Super+A: R и V действуют так же
- [ ] 5.3 Посторонние клавиши (Q, Alt+Tab, Super+Delete) в состоянии «Поднять» поглощаются; при русской раскладке V и R действуют так же, как при английской
- [ ] 5.4 Escape из состояния «Новое окно» и Backspace из корня закрывают цепочку, индикатор исчезает, Super+S открывает окно выбора сессии

## 6. Документация

- [ ] 6.1 `AGENTS.md`, раздел «Сессия Hyprland»: абзац о цепочке Super+A (состояния, Backspace, Escape, индикатор) и о ключе `--new`
- [ ] 6.2 Шапка раздела привязок в `config.toml` — ссылка на раздел `[sticky]`; `openspec validate sticky-chains --strict`; архивация после `keys-help`, `live-layout`, `work-area-center`, `session-instances`, `askpass-only-quickshell`
