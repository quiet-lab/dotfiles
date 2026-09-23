# Дела репозитория dotfiles

## Текущая работа

Снимок на 2026-09-24 (ночь). Файл хранится в git, но в `$HOME` не попадает: он исключён в `.chezmoiignore`.

### Цель

Серия изменений модели окон демона workspaced по [`docs/window-model.md`](docs/window-model.md) реализована целиком (шаги 1–6 заархивированы, шаг 7 ждёт проверки перезагрузкой). Сверх серии за 23.09.2026 сделаны и ждут закрытия: раскладка workspace в памяти (`live-layout`), центр окон по рабочей области (`work-area-center`), окно пароля только на Quickshell (`askpass-only-quickshell`), цепочки клавиш с выходом (`sticky-chains`) и превращение всех многошаговых цепочек в липкие (`chains-sticky`). Конфиг сессии и поведение остального не меняются: остаётся довести проверки пользователем и заархивировать изменения по порядку.

### Открытые вопросы к пользователю

- Проверка нажатиями изменения `chains-sticky` (пункты 4.1–4.4 его [`tasks.md`](openspec/changes/chains-sticky/tasks.md)): Super+Tab даёт карточку в правом нижнем углу, Q поглощается, S/W/Tab выполняют действие и закрывают режим; Ctrl+Super+S и, не отпуская модификаторы, S — снимок сессии; Ctrl+Super+S, затем W без модификаторов — поглощается, Ctrl+Super+W — запись workspace (после неё откатить конфиг `chezmoi apply --force ~/.config/workspaced/config.toml`); Backspace и Escape закрывают режим без действия. Предложена 23.09.2026, ответа не было.
- Проверка перезагрузкой изменения `session-instances` (пункт 4.1 его [`tasks.md`](openspec/changes/session-instances/tasks.md)): перед ней открыть второе окно Chromium в `work` и второй neovide, нажать Ctrl+Super+S дважды, перезагрузиться — после входа состояние должно вернуться с экземплярами и общими окнами; во всех четырёх профилях браузеров включено «продолжить с того же места», поэтому вторые окна браузеров должны вернуться. Итог дописать в `docs/host-state.md` (пункт 5.4 того же `tasks.md`).

### Где остановились

- Демон на коммите `1e395ff` (`~/work/pets/workspaced`, `master`, 156 тестов), служба `workspaced.service` работает на этом бинарнике. В нём: шаги 1–7 модели окон, раскладка в памяти, центр по рабочей области, `[sticky.<имя>]` и липкие многошаговые цепочки, `key --new`/`app --new`, `keys --json` с группами и режимами.
- Панель: плитка активного стола с табами, общее окно в плитках обоих столов, кнопка «+k» поверх ряда, окно подсказки клавиш (Shift+Super+/, 1920 px, одна колонка, плавная прокрутка, клавиши в духе Vim), карточка режима цепочек в правом нижнем углу; оформление `Theme`/`Tile` в общем модуле `dot_config/quickshell/common` (`qs.common`), его же использует окно пароля.
- Окно пароля sudo — только Quickshell: запасной pinentry удалён, `Path askpass` в `/etc/sudo.conf` (копия `system/sudo/`), `SUDO_ASKPASS` в окружении сессии, правило в общем `CLAUDE.md` и `AGENTS.md`, запись [`0008`](docs/decisions/0008-askpass-quickshell-only.md). Агент polkit на Quickshell — отдельная доработка (раздел «Панель Quickshell» ниже).
- Раскладка после диктовки VoxType возвращается перехватом `post_output_command` (обход ошибки Hyprland, вопрос [`hyprland-keymap-group-after-virtual-keyboard.md`](docs/open-questions/hyprland-keymap-group-after-virtual-keyboard.md)); dunst удалён, скрипты на `notify-send`.
- Проверены пользователем и ждут только архивации: `live-layout` (4.1–4.3), `work-area-center` (5.1–5.2), `askpass-only-quickshell` (5.1–5.2), `sticky-chains` (5.1–5.4). `keys-help`, `shared-windows`, `workspace-overrides`, `panel-shared-windows`, `move-desktop-*`, `ws-tile-*`, `classless-windows-stay-free`, `voxtype-restore-layout`, `dunst-removed` — в архиве.
- Параметр `conceal_vrr_caps` действует с ближайшей перезагрузки ([`0006`](docs/decisions/0006-nvidia-conceal-vrr-caps.md)).
- Рабочие деревья chezmoi (`main`) и `~/work/pets/workspaced` (`master`) чисты, всё отправлено в `origin`.

### Следующие шаги

1. Получить итоги проверки `chains-sticky` нажатиями, отметить 4.1–4.4 в его `tasks.md`; при отказе — исправить и повторить.
2. Провести проверку перезагрузкой (`session-instances`, 4.1); заодно после перезагрузки проверить `conceal_vrr_caps` (команда `status` ниже, DP-2 на 120 Гц) и остановку `graphical-session.target` при выходе (раздел «Hyprland» ниже). Итог записать в `docs/host-state.md`, отметить 4.1 и 5.4.
3. Архивировать по порядку, после каждого — `openspec validate --specs`: `session-instances` → `live-layout` (пункты 5.1–5.2) → `work-area-center` (6.1; после него проверить, что в `openspec/specs/hyprland-binds/spec.md` есть строки Shift+Super+/ и Alt+Super+Enter) → `askpass-only-quickshell` (6.1) → `sticky-chains` (6.3) → `chains-sticky` (5.2). Ссылки на изменения в `docs/window-model.md` перевести на архивные.
4. Комментарии в демоне: к запуску записей без workspace ссылка на D16 вместо D17 (`session-instances`, пункт 5.7) — поправить при следующей правке `daemon.rs`.
5. Агент polkit на Quickshell (`Quickshell.Services.Polkit`) — отдельное изменение по плану D5 из `openspec/changes/askpass-only-quickshell/design.md`.
6. После 23.10.2026 снова спросить пользователя об отправке черновиков из `docs/upstream/` (условие пересмотра в `docs/open-questions/hyprland-window-parent.md`).

### Как проверить

```bash
openspec list                              # активны: chains-sticky, session-instances, live-layout, sticky-chains, askpass-only-quickshell, work-area-center
openspec validate --specs                  # 20 passed
systemctl --user is-active workspaced.service quickshell-panel.service voxtype.service voxtype-mute-others.service
workspaced check && workspaced keys --list | rg 'SUPER\+TAB|SUPER\+CTRL\+s|SUPER\+S '   # цепочки с exit, режим sticky.apps
workspaced status --json | jq -c '.desktops | to_entries | map({(.key): [.value.active, [.value.workspaces[].name]]}) | add'
qs -c panel ipc call keys state; qs -c panel ipc call chains state; qs -c panel ipc call workspaces row 1
journalctl --user -t voxtype-restore-layout -n 3   # вызовы после диктовки
env -u SUDO_ASKPASS sudo -A -p 'Проверка окна пароля' true   # окно Quickshell, Escape даёт код 1
system/modprobe.d/nvidia-vrr.sh status    # после перезагрузки ожидается conceal_vrr_caps = Y
chezmoi status && git status -sb          # расхождений и незакоммиченного быть не должно
```

### Что пробовали и отвергли

- Относить окно браузера, открытое по Ctrl+N, к приложению активного окна: признак ненадёжен, подробности в `docs/window-model.md`.
- Правило окна `focus_on_activate = false` для Telegram: отключило бы переход к топику по клику на уведомление.
- Таймеры вместо событий (подсказки, переподключение панели, срок показа уведомлений, ожидание клавиши в режиме): пользователь велел обходиться событиями (`docs/decisions/0007-no-timers.md`).
- Судить о загрузке новой карты XKB по `hyprctl devices` или по работе нового сочетания: список раскладок берётся из старой карты.
- Хранить `~/.claude/settings.json` сценарием `modify_`: пользователь решил держать файл целиком.
- Брать текущий стол для команд демона из кэша событий композитора: отставшее событие возвращает прежний стол.
- Плагин Hyprland ради признака диалога: для браузеров бесполезен (Chromium не сообщает родителя), стоит сборки под каждую версию.
- Ctrl+Enter как клавиша «не беспокоить»: нужна приложениям (отправка сообщений в Telegram).
- Окно столбика уведомлений ростом со столбик: композитор анимировал бы каждое изменение размера; окно постоянного размера с областью ввода по карточкам.
- Отменять обмен мест при запуске приложения без окон (коммит демона 260d88b): пользователь подтвердил действующее правило «запуск без окон переводит приложение на главное место», коммит откачен (eb8b0bb).
- Запасной pinentry у окна пароля, `input:virtualkeyboard:share_states` как лечение раскладки после диктовки, три колонки и центр всего экрана у окна подсказки, карточка режима вверху экрана — отвергнуты пользователем 23.09.2026.

## Возможные доработки

Замечания и идеи, которые всплыли по ходу и не вошли в спецификации; каждое при желании оформляется новым изменением. Вопросы, по которым решение сейчас принять нельзя, здесь не хранятся: они лежат отдельными файлами в `docs/open-questions/`.

### Демон workspaced

- [ ] Демон не переживает сессию, в которой у активного workspace нет монитора (экран выключен, Hyprland на выходе FALLBACK): восстановление сессии падает на `hl.dsp.focus({ workspace = … })` с ошибкой «Workspace has no monitor», и юнит после пяти попыток встаёт в `failed`. Обнаружено 22.09.2026 при перезапуске юнита с выключенным экраном; то же случится при перезаходе в сессию без монитора. Нужно либо откладывать восстановление до появления монитора, либо не считать эту ошибку смертельной.
- [ ] Запускать приложения в отдельный transient scope (`systemd-run --user --scope` или эквивалент через D-Bus), чтобы при `KillMode=process` они не оставались в cgroup демона: systemd при следующем старте пишет «Found left-over process», а память приложений учитывается демону.
- [ ] `Alt+Tab` обходит окна стола по порядку создания (`stable_id`). Если захочется порядок «по последнему использованию», нужен обработчик с удержанием Alt (флаг `release`) либо команда демона с собственной историей фокуса.
- [ ] Обход окон стола стрелками вместо `Alt+Tab`: вверх и влево — к предыдущему окну, вниз и вправо — к следующему. Отложено на отдельное обсуждение 2026-09-16.
- [ ] Парковать вытесненные окна за краем экрана, а не на `special:pool`: Hyprland сохраняет положение окна, вынесенного за пределы экрана (проверено 2026-09-16). Отложено на отдельное обсуждение.

### Панель Quickshell

- [ ] Таймеры панели, помеченные `WARNING`: опрос без источника событий остался в трёх местах — `tiles/Gauges.qml` (нагрузка CPU и GPU, память, температуры: `/proc` и `/sys` об изменении значений не сообщают; 3 с и 5 с), `tiles/Disks.qml` (заполнение файловых систем: у `statfs` уведомлений нет; 30 с; появление и монтирование дисков можно будет перевести на события udev, заполнение — нет), `tiles/Weather.qml` (wttr.in отвечает только на запрос; 30 минут). Объяснения — в комментариях над таймерами.
- [ ] Предупреждения при старте о недостающих файлах значков: выбрать одно из двух — либо считать вопрос закрытым (комментарий в `AppIcon.qml` уже объявляет эти предупреждения ожидаемыми: перебор кандидатов и есть способ найти значок), либо проверять существование файла до подстановки в `AppIcon`, чтобы журнал не засорялся. По `journalctl --user -u quickshell-panel.service` не находятся значки musique, herdr, com.heroicgameslauncher.hgl, wine, protontricks, ncmpcpp (вместе с записями ncmpcpp.album-art и ncmpcpp.single.album-art) и steam_app_1363080 — по несколько сотен строк за сессию.
- [ ] Агент polkit на Quickshell: модуль `Quickshell.Services.Polkit` (типы `PolkitAgent`, `AuthFlow`) есть в Quickshell 0.3.1; агент в процессе панели, окно в оформлении `qs.common` как у askpass, `hyprpolkitagent.service` замаскировать. План — решение D5 в [`design.md`](openspec/changes/askpass-only-quickshell/design.md) изменения `askpass-only-quickshell`; оформляется отдельным изменением.
- [ ] `Theme.margin` и `Theme.gap` (10 px) и `gap` демона (5 px) живут в двух файлах; правило одинаковых расстояний записано комментариями в обоих и в CLAUDE.md. Если появится третье место, вынести число в одно.

### Hyprland

- [ ] Правило окна `opaque-modal` в `hyprland.lua` (`match = { modal = true }`) на нативные окна Wayland не действует: `CWindow::isModal()` в Hyprland 0.56 смотрит только на `_NET_WM_STATE_MODAL` окон XWayland (найдено 22.09.2026 при пробе о диалогах). Решить, нужно ли правило вообще.
- [ ] Открытый вопрос из design hyprland-config: нужен ли `xwayland.force_zero_scaling` для приложений Xwayland на 4K. Второй вопрос того же перечня закрыт: `misc.focus_on_activate` в `hyprland.lua` включён.
- [ ] После обновления Hyprland сверять `hl.bind` (флаги `drag`/`mouse`) и аргументы `cycle_next` с `/usr/share/hypr/stubs/hl.meta.lua`.
- [ ] При следующем выходе из сессии проверить, что `graphical-session.target` действительно останавливается. Спецификация hyprland-session этого требует, обработчик `hl.on("hyprland.shutdown")` в `hyprland.lua` есть, но выход из Hyprland завершался сегфолтом в деструкторе DRM-бэкенда aquamarine, и тогда обработчик не срабатывает. Проверка: после возврата в tuigreet и нового входа посмотреть `systemctl --user status graphical-session.target` и журнал прошлой сессии.

### Система

- [ ] Ярлыки `~/.local/share/applications/fedora-box-*.desktop` лежат вне chezmoi, а добавленные в них руками ключи Wayland и VA-API повторный `distrobox-export` перезапишет. Решить, брать ли ярлыки под chezmoi. Запуск браузеров клавишами демона (Super+B/V/Y и Shift+Super+B/V/Y) от них не зависит: те же ключи продублированы в аргументах приложений демона.

### Инструменты агента

- [ ] Для проверок нажатиями из оболочки нужен ydotool (uinput): `wtype` привязки композитора не запускает. Пока проверки делает пользователь.
