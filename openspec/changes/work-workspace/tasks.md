## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: поля `class` и `title` у `App`, раздел `[startup]` (`workspace`, `desktop` по умолчанию 1); проверка компилирует выражения, отклоняет `title` без `class`, неизвестный `startup.workspace` и стол вне 1…8; тесты на принятие и на каждую ошибку
- [x] 1.2 `daemon.rs`: проход захвата `adopt_untagged` по design D2–D3 в начале `raise` и `app`: кандидаты без тега или с тегом отсутствующего приложения, не на `special:hidden`, совпадение класса и заголовка, перестановка тегов в композиторе и в локальном списке; модульный тест выбора кандидата (два wezterm с разными заголовками, окно с тегом удалённого приложения, окно на hidden)
- [x] 1.3 `daemon.rs`: `startup` поднимает `[startup].workspace` на его столе после восстановления сессии; `cargo test` проходит, `cargo build --release`
- [x] 1.4 `daemon.rs`: ожидаемое окно сопоставляется и по `class`/`title` приложения (`Pending::matches`, `matcher_fits`), так как окно из контейнера не потомок `distrobox-enter`; модульный тест; `cargo test`, `cargo build --release`

## 2. Конфиг и автозапуск

- [x] 2.1 `dot_config/workspaced/config.toml`: приложения `herdr` (`wezterm-gui start --always-new-process -- herdr`, cwd `~`, class wezterm, title `^herdr · `, chain `SUPER+T`), `chromium` (class `(?i)^chromium(-browser)?$`, chain `SUPER+C`), `neovide` (class `^neovide$`, chain `SUPER+E`); workspace `work` на `thirds` (herdr — center и main, chromium — left, neovide — right, chain `SUPER+TAB w`, иконка `folder-development`); `[startup] workspace = "work"`; удалены прочие приложения, workspace, записи со столом, запись Super+E для thunar; закрытие окна на `SUPER+Delete`; `SUPER+T` убран из `reserved`. `chezmoi apply`, `workspaced check` без ошибок, `workspaced keys --list` показывает T/C/E, Delete и `SUPER+TAB w`
- [x] 2.2 Перезапустить демон, `hyprctl reload config-only`; `workspaced raise work`: Chromium, wezterm с herdr и neovide захвачены (`hyprctl clients -j` показывает теги `app:chromium`, `app:herdr`, `app:neovide`), расставлены по ячейкам thirds (окна 1125…3045, −805…1115, 3055…4975), лишние приложения не запущены
- [x] 2.3 `dot_config/hypr/hyprland.lua`: удалить `hl.exec_cmd("wezterm-gui")` и `hl.exec_cmd("firefox")`; `chezmoi apply`, `hyprctl reload config-only` без ошибок
- [x] 2.4 Workspace `surf` (halves, `chrome` справа и главный, `chrome-ai` слева, `SUPER+TAB s`), приложения `chrome` (`SUPER+B`) и `chrome-ai` (`SUPER+V`) через `distrobox-enter -n ubuntu-box`, `save_workspace = "SUPER+TAB SUPER+s"`, меню буфера обмена на `SUPER+Insert`; два открытых окна помечены тегами по профилям (по файлам сессий Chrome), `workspaced raise surf --desktop 2`

## 3. Проверка вживую (пользователь)

- [ ] 3.1 Super+T, Super+C, Super+E делают главным herdr, Chromium, neovide (обмен ячеек), Super+Delete закрывает активное окно, Super+Tab w поднимает work
- [x] 3.2 Перезаход в сессию: без терминала и Firefox из автозапуска, work поднят на столе 1 с тремя окнами по ячейкам
- [ ] 3.3 Super+B и Super+V делают главным окно нужного профиля Chrome, Super+Tab s поднимает surf, Super+Tab Super+S сохраняет workspace, Super+Insert открывает меню буфера обмена

## 4. Спецификации и документация

- [x] 4.1 `openspec validate work-workspace --strict` проходит; AGENTS.md: описание привязок (Super+T/C/E, Super+Delete, единственный workspace work, раздел `[startup]`, захват окон по `class`/`title`)
- [x] 4.2 Проход по формулировкам артефактов, комментариев в коде и конфиге
