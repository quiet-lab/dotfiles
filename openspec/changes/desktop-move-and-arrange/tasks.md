## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: действие `{ move = <стол> }` в записи `[[binds]]` (число или строка — в записи с `range` там `$n`) и служебное действие `"arrange"`. Проверка: модульный тест `move_desktop_and_arrange_actions`, `cargo test`
- [x] 1.2 `keys.rs`: разворачивание серии подставляет `$n` и в действие `move`; привязки дают команды `workspaced move-desktop <n>` и `workspaced arrange`; номер стола проверяется после разворачивания серии, стол вне 1…8 отклоняется с указанием цепочки. Проверка: тот же тест, `workspaced keys --list`
- [x] 1.3 `main.rs`: подкоманды клиента `move-desktop <стол>` и `arrange`, команды сокета `move-desktop` и `arrange`
- [x] 1.4 `daemon.rs`: `move_desktop` — перенос активного workspace текущего стола на другой стол поднятием с явным столом; перед переносом запоминаются фактические прямоугольники окон (режим `stack`), без активного workspace и при переносе на тот же стол команда только пишет в журнал. Проверка: `cargo test`, `cargo clippy --all-targets -- -D warnings`
- [x] 1.5 `daemon.rs`: `arrange` — расстановка окон текущего стола по описанию активного workspace; чистая логика в `arrange_plan` (место приложения по правилу мест, окна без описания стопками по классу в положение по умолчанию `center_rect`); в режиме `stack` запомненные прямоугольники сменяются местами из конфига; фокус остаётся у активного окна, оно поднимается наверх. Проверка: модульный тест `arrange_plan_places_apps_and_stacks_free_windows`
- [x] 1.6 `hypr.rs`: поле `stableId` у окна и порядок появления (`Client::stable`) — по нему выбирается первое окно класса в стопке свободных окон
- [x] 1.7 `daemon.rs`: обе команды меняют состояние, поэтому снимок сессии пишется до ответа клиенту (`changes_state`). Проверка: тест `only_state_changing_commands_write_the_snapshot`
- [x] 1.8 Сборка и проверки: `cargo test` (62 теста), `cargo clippy --all-targets -- -D warnings`, `cargo build --release` — чисто
- [x] 1.9 Исправление по итогам проверки командами: `move-desktop` и `arrange` читают текущий стол у композитора и приводят к нему кэш `current` (`sync_current`), решение о действии вынесено в чистую функцию `move_step`. Причина: отставшее событие `workspacev2` возвращало в кэш прежний стол, и второй `move-desktop 3` подряд переносил workspace со стола 1. Проверка: модульный тест `move_step_by_current_and_target_desktop`

## 2. Карта XKB (`dot_config/X11/xkb_custom`)

- [x] 2.1 Тип `SUPER_SPACE_GROUP_TOGGLE`: маска `Shift+Lock+Control+Mod1+Mod4`, второй уровень ровно при `Mod4`, остальные 30 сочетаний маски — первый уровень с `preserve`; опция `group(win_space_toggle)` убрана из include, клавиша `<SPCE>` описана целиком (`ISO_Next_Group` и `LockGroup(group=+1)` явно). Комментарии в шапке файла и у типа объясняют причину
- [x] 2.2 Проверка сборки карты: `xkbcli compile-keymap --keymap dot_config/X11/xkb_custom` — в собранной карте у типа один `map[Mod4]= 2`, у остальных сочетаний маски уровень 1 и сохранённые модификаторы
- [x] 2.3 Применение без выхода из сессии: `chezmoi apply --force ~/.config/X11/xkb_custom`, затем перезагрузка карты композитором приёмом из `docs/agent-session-tips.md` (подмена строки `kb_file` и возврат файла). Проверка: в журнале Hyprland «Attempting to create a keymap» для физических клавиатур, `hyprctl configerrors` пуст, `chezmoi status` пуст

## 3. Конфиг сессии (`dot_config/workspaced/config.toml`)

- [x] 3.1 Записи `[[binds]]`: `chain = "CTRL+SUPER+$n"` с `range = [1, 8]` и `action = { move = "$n" }`; `chain = "CTRL+SUPER+space"` с `action = "arrange"`; комментарий у `reserved` объясняет, почему Ctrl+Super+Пробел занимать теперь можно. Проверка: новый бинарник с временным `XDG_CONFIG_HOME` — `workspaced check` без ошибок, `workspaced keys --list` показывает восемь `move-desktop 1…8` и `arrange`
- [ ] 3.2 Применить конфиг (`chezmoi apply --force ~/.config/workspaced/config.toml`), перезапустить `workspaced.service` с новым бинарником, проверить `workspaced check` и `workspaced keys --list` на живом конфиге. Откладывалось: прежний демон стоял на проверке у пользователя, а конфиг с действием `move` он отклонил бы

## 4. Спецификации и документация

- [x] 4.1 Дельты спецификаций: ws-daemon (новые требования «Перенос workspace на стол» и «Расстановка по команде», «Поднятие workspace на столе» упоминает команду переноса), ws-config («Цепочки клавиш и привязки»), hyprland-binds (таблица раскладки и зарезервированные сочетания), hyprland-config (карта XKB), hyprland-session (условие совместимости). Дельты сняты с основных спецификаций уже после архивации `key-cycle-stack`
- [x] 4.2 `openspec validate desktop-move-and-arrange --strict` проходит
- [x] 4.3 `AGENTS.md`: новые цепочки и правило про Super+Пробел
- [x] 4.4 `docs/window-model.md`: расстановка по команде в разделе 2.4 и перенос workspace в разделе 2.5
- [x] 4.5 Спецификация qs-tray-lang не правится: её фраза «сочетания Win+Alt+E, Win+Alt+R и Win+Пробел продолжают переключать раскладку сами» после правки карты верна
- [x] 4.6 Отдельный проход по формулировкам: артефакты изменения, комментарии в `config.toml`, `xkb_custom` и в изменённом коде демона

## 5. Проверка вживую (пользователь)

- [ ] 5.1 На столе 2 (`surf`): сдвинуть окно мышью, нажать Ctrl+Super+3 — workspace целиком переезжает на стол 3 вместе со всеми окнами, сдвинутое окно стоит там, куда его сдвинули; Ctrl+Super+2 возвращает `surf` на стол 2; повторное Ctrl+Super+3 на столе 3 ничего не делает, а не забирает workspace соседнего стола
- [ ] 5.2 На столе 1 (`work`): растащить окна мышью и нажать Ctrl+Super+Пробел — окна приложений возвращаются в свои ячейки; два окна программы, не описанной в конфиге, встают стопкой в центр экрана; фокус остаётся у того окна, которое было активным
- [ ] 5.3 Раскладка: Ctrl+Super+Пробел, Alt+Super+Пробел и Shift+Super+Пробел раскладку не переключают, Super+Пробел переключает; проверка нажатиями в поле ввода, потому что `hyprctl devices` показывает раскладки прежней карты
