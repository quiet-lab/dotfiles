# Дела репозитория dotfiles

## Текущая работа

Снимок на 2026-11-07. Файл хранится в git, но в `$HOME` не попадает: он исключён в `.chezmoiignore`.

### Цель

Сессия Hyprland с демоном workspaced и панелью Quickshell доведена до нынешнего вида; модуль Neovim `ru-layout` (русская раскладка независимо от хоста), панель ввода `claude-input`, сторож внимания демона и следование herdr за диалогами агентов работают. Остаётся закрыть одиннадцать активных изменений OpenSpec: их дельты сведены для последовательной архивации, архивацию держат только проверки пользователя и одна перезагрузка. Конфиг сессии и поведение остального не меняются.

### Открытые вопросы к пользователю

- Перезагрузка: пункт 4.1 [`session-instances`](openspec/changes/session-instances/tasks.md) и пункт 3.4 [`session-windows-transient`](openspec/changes/session-windows-transient/tasks.md) (действия до неё — в тексте задач). После входа агент сверяет журнал демона и `hyprctl clients -j`, затем архивирует цепочку. Той же перезагрузкой проверяются `snapshot-stale-rects` и `snapshot-stale-section`: окна `work` встают по `thirds-split`, при подъёме `surf` по Super+V Chrome AI слева и Chrome AI2 справа.
- [`enter-backspace-keys`](openspec/changes/enter-backspace-keys/tasks.md), 5.5: при непустой истории уведомлений Shift+Super+Backspace — история пуста, число на плитке исчезло.
- [`toggle-windows`](openspec/changes/toggle-windows/tasks.md), 4.2: при спрятанном Telegram приходит настоящее сообщение, левый клик по карточке — окно с топиком на текущем столе, окна `special:pool` не мелькают заметно. Пункт 4.3: клик по значку Telegram в трее при спрятанном окне — окно 1500×1500 по центру с фокусом.
- [`notifications-top-stack`](openspec/changes/notifications-top-stack/tasks.md), 4.1: оценить вид столбика уведомлений.
- Проверка кликами значков туннелей в трее (изменение `tunnel-tray-autostart`, архив): левый клик по верхнему значку (`amn0`) открывает справа от колонки окно со строками «Endpoint», «Handshake», «Элементов zones» и журналом, клик вне окна закрывает его; правый клик по значку `axata` открывает меню «Отключить», «Настройки». Действия меню без нужды не выбирать: через туннели работают агенты.
- Проверка кликами выбора страны (изменение `tunnel-country-link`, архив): правый клик по значку `amn0` → «Страна туннеля…» открывает сетку стран с выделенной текущей (Франция); выбор другой страны перезапускает `amn0` (обрыв на 10–20 с), после чего в окне сведений строки «Страна» и «Выход» совпадают.
- Проверка состояния «поднят, связи нет» настоящим обрывом (изменение `tunnel-country-link`, архив): `sudo -A -p 'Проверка связи amn0' nft 'add table inet amntest; add chain inet amntest out { type filter hook output priority 0; }; add rule inet amntest out ip daddr <адрес Endpoint amn0> drop'` — значок `amn0` через 10–15 с оранжевый, подсказка называет «Handshake did not complete … (try 3)»; `sudo -A -p 'Конец проверки связи amn0' nft delete table inet amntest` — снова зелёный. Трафик через `amn0` на время проверки прерывается, поэтому её делает пользователь, когда через туннель никто не работает. Для `axata` проверки нет: профиль без `ping-restart` (решение пользователя, `docs/amnezia-split-tunnel.md`).
- Проверка перезагрузкой автозапуска туннелей (изменение `tunnel-tray-autostart`, архив) и чистого старта herdr (изменение `herdr-prestart`, архив): после входа оба значка туннелей зелёные, в выводе `journalctl -b -o short-monotonic -u awg-quick@amn0 -u axata-vpn -u tunnels-before-login -u greetd | grep -E 'Starting|Finished|Started'` строки `Finished` у `awg-quick@amn0` и `axata-vpn` стоят раньше `Started` у `greetd`; `journalctl --user -b -u herdr-prestart` содержит итог `claude update`, `herdr update`, интеграции и строку о переименовании `session.json`, окно herdr показывает одно пространство в `~/work/telecom/axata/monorepo-ocp`, `pgrep -x claude` пусто. Итог по туннелям — в `docs/amnezia-split-tunnel.md`, раздел «Автозапуск туннелей».
- Отправка черновиков из `docs/upstream/` (отчёты Hyprland и Chromium о родителе окна): срок, на который решение было отложено, истёк 23.10.2026, вопрос задаётся снова ([`hyprland-window-parent.md`](docs/open-questions/hyprland-window-parent.md)).
- Оценка следования herdr за диалогами агентов, фокуса панели ввода и паузы видео при вопросе: пользователь перезапускает клиент herdr, Neovim/Neovide и сессии Claude Code сам, позже.

### Где остановились

- Деревья chezmoi (`main`) и `~/work/pets/workspaced` (`master`, `ca1db63`) чисты, всё отправлено в `origin`.
- OpenSpec: 11 активных изменений, каждое проходит `openspec validate <имя> --strict`. Порядок архивации одной командой на изменение: `session-instances` → `live-layout` → `work-area-center` → `askpass-only-quickshell` → `sticky-chains` → `chains-sticky` → `session-windows-transient` → `toggle-windows` → `shared-app-chain` → `enter-backspace-keys`; `notifications-top-stack` вне цепочки. Симуляция архивации в копии прошла. Основные спецификации `hyprland-binds` и `ws-config` приведены к живому поведению. Живые проверки ydotool прошли: `session-windows-transient` 3.3, 3.5; `enter-backspace-keys` 5.1–5.4; `shared-app-chain` 5.1–5.2; `toggle-windows` 4.1, 4.3 (по D-Bus), 4.4 ([`report.md`](/home/mne/.local/state/duty/dotfiles/results/openspec-reconcile/report.md), `live-checks/results.md` рядом).
- `openspec validate --specs` падает на длинных требованиях и до этого, им не пользоваться: проверка идёт по каждому изменению с `--strict`.
- Neovim: модуль `ru-layout` (формы `<C-В>`, `<M-C-в>`, независимость от wezterm и Neovide; [`docs/ru-layout.md`](docs/ru-layout.md)), изменение заархивировано. `claude-input`: виртуальный перенос, буфер диалога закрывается после `:w`, `<S-CR>` и `<S-Space>` подтверждают выбор, панель ввода у любой сессии Claude Code, хук открывает её только через `herdr pane activate` (изменение `input-pane-activate-only`), токен `input_pane` на панели; TabNine удалён ([`docs/claude-input.md`](docs/claude-input.md)). Проверка набора `claude-input-buffer` 6.1 закрыта: панель используется ежедневно.
- workspaced `[attention]`: пауза MPRIS, остановка игры сигналом SIGSTOP, фокус herdr при вопросе агента. В `~/.config/herdr/config.toml` включено `[ui.follow_blocked] enabled = true`, форк herdr `duty-v0.9.5.7`.
- Перестановка ячеек `work` после перезапуска workspaced разобрана: причина — Super+C пользователя в режиме `home`, дефекта демона нет ([`report.md`](/home/mne/.local/state/duty/workspaced/results/ws-restore-cells/report.md)).
- Панель: четыре плитки столов, правая колонка вровень, заливка плиток 0.8 (`Theme.tileBg`). Размытие и прозрачность в `hyprland.lua` подобраны; варианты размытия ждут Hyprland 0.57 в pacman ([`hyprland-blur-variants.md`](docs/open-questions/hyprland-blur-variants.md); сейчас 0.56.2).
- Super+Shift+Пробел намеренно свободен. Окно пароля sudo — только Quickshell ([`0008`](docs/decisions/0008-askpass-quickshell-only.md)); раскладка после диктовки VoxType возвращается перехватом `post_output_command` ([`hyprland-keymap-group-after-virtual-keyboard.md`](docs/open-questions/hyprland-keymap-group-after-virtual-keyboard.md)).

### Следующие шаги

1. После ответов пользователя и перезагрузки: сверить журнал и `hyprctl clients -j`, плитку стола 1 (`qs -c panel ipc call workspaces row 1`), `conceal_vrr_caps = Y` (`system/modprobe.d/nvidia-vrr.sh status`); итог дописать в `docs/host-state.md`, отметить 4.1 и 5.4 `session-instances`.
2. Архивировать цепочку в порядке из «Где остановились» (`openspec validate <имя> --strict`, затем `openspec archive <имя> -y`), `notifications-top-stack` — после оценки вида. Ссылки в `docs/window-model.md` перевести на архивные.
3. Дефект демона: поднятие workspace и `workspaced arrange` при полноэкранном окне завершаются ошибкой композитора «Window is fullscreen» (демон двигает такое окно), окна расставляются верно — пропускать полноэкранные окна или снимать ошибку.
4. Дефект демона: правка геометрии ячеек шаблона при работающем демоне раскладку не пересобирает (`keep_layout` сравнивает только разделы workspace) — учесть шаблон в сравнении; записан в `design.md` изменения `snapshot-stale-rects`.
5. Комментарий в `daemon.rs`: к запуску записей без workspace ссылка на D16 вместо D17 (`session-instances`, пункт 5.7) — при следующей правке.
6. Агент polkit на Quickshell (`Quickshell.Services.Polkit`) — отдельное изменение по плану D5 из `openspec/changes/askpass-only-quickshell/design.md`.
7. По желанию пользователя: понизить до info предупреждение демона «исполняемый файл команды … не найден» для процессов из контейнера distrobox (`proc_info`, `src/daemon.rs`); оно повторяется при каждом захвате окна браузера из `fedora-box`.

### Как проверить

```bash
openspec list                              # 11 активных изменений
for c in $(openspec list --json | jq -r '.changes[].name'); do openspec validate $c --strict; done
cd ~/.config/nvim/local/ru-layout && bash tests/run-all.sh   # тесты ru-layout
herdr --version                            # duty-v0.9.5.7
systemctl --user is-active workspaced.service ydotool.service
workspaced check && workspaced status --json | jq -c '.desktops | to_entries | map({(.key): [.value.active, [.value.workspaces[].name]]}) | add'
journalctl --user -u workspaced.service -b | rg 'собирается заново из конфига|не действуют'
SIG=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1); HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl clients -j | jq -c '.[] | {class, ws: .workspace.name, at, size, fullscreen}'
cd ~/work/pets/workspaced && cargo test 2>&1 | tail -3   # 209 passed
chezmoi status && git status -sb          # расхождений и незакоммиченного быть не должно
```

Тесты `claude-input`: `cd dot_config/nvim/local/claude-input && nvim --headless --clean -u NONE -l tests/switch_spec.lua && nvim --headless --clean -u NONE -l tests/dialog_spec.lua` — ALL OK ([`docs/claude-input.md`](docs/claude-input.md)).

### Что пробовали и отвергли

- Снимать и снова ставить fullscreen или `bring_to_top` для полноэкранного окна: браузер выходит из полноэкранного видео, `bring_to_top` ставит признак самому окну, соседям не снимает ([`design.md`](openspec/changes/archive/2026-10-23-fullscreen-raise/design.md)).
- Считать прямоугольник окна из снимка устаревшим, если он не совпадает ни с ячейкой, ни с `moved`: второй экземпляр, сдвинутый мышью, законно стоит вне обоих ([`design.md`](openspec/changes/archive/2026-10-24-snapshot-stale-rects/design.md)).
- Размытие `size 9, passes 1` двоит картинку; `hyprland-git` из AUR ради вариантов размытия пользователь отверг.
- Таймеры вместо событий ([`0007`](docs/decisions/0007-no-timers.md)); правило окна `focus_on_activate = false` для Telegram отключило бы переход к топику по клику на уведомление.
- Запускать общее окно при восстановлении сессии вторым экземпляром там, где его приложение не описано в конфиге: общие окна остаются общими; запасной pinentry у окна пароля отвергнут.
- `openspec validate --specs` как общая проверка: падает на длинных требованиях, заменена проверкой каждого изменения с `--strict`.

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
- [ ] Таймер в `hyprland.lua` (обработчик `window.fullscreen`, помечен `WARNING`): окно защиты 50 мс от повторного запроса maximized после выхода из fullscreen в Chromium ([`0007`](docs/decisions/0007-no-timers.md)). Причина: Hyprland не сообщает события, по которому можно снять `fullscreen_just_left`, и не даёт отличить повторный запрос от настоящего. Заменить, когда появится такое событие или признак, либо когда будет исправлено обсуждение Hyprland #13322.
- [ ] После обновления Hyprland сверять `hl.bind` (флаги `drag`/`mouse`) и аргументы `cycle_next` с `/usr/share/hypr/stubs/hl.meta.lua`.
- [ ] При следующем выходе из сессии проверить, что `graphical-session.target` действительно останавливается. Спецификация hyprland-session этого требует, обработчик `hl.on("hyprland.shutdown")` в `hyprland.lua` есть, но выход из Hyprland завершался сегфолтом в деструкторе DRM-бэкенда aquamarine, и тогда обработчик не срабатывает. Проверка: после возврата в tuigreet и нового входа посмотреть `systemctl --user status graphical-session.target` и журнал прошлой сессии.

### Система

- [ ] Ярлыки `~/.local/share/applications/fedora-box-*.desktop` лежат вне chezmoi, а добавленные в них руками ключи Wayland и VA-API повторный `distrobox-export` перезапишет. Решить, брать ли ярлыки под chezmoi. Запуск браузеров клавишами демона (Super+B/V/Y и Shift+Super+B/V/Y) от них не зависит: те же ключи продублированы в аргументах приложений демона.

### Инструменты агента

- [ ] Перезапустить herdr (закрыть, открыть по SUPER+W) и проверить на экране значки состояния и цвета заголовков spaces из `[ui.status_icons]` и `[ui.sidebar.spaces]`: станция уже на форке (`~/.local/bin/herdr`), пакета `herdr-bin` и `herdr-update.service` нет.
