# Дела репозитория dotfiles

## Текущая работа

Снимок на 2026-11-08. Файл хранится в git, но в `$HOME` не попадает: он исключён в `.chezmoiignore`.

### Цель

Сессия Hyprland с демоном workspaced и панелью Quickshell доведена до нынешнего вида; модуль Neovim `ru-layout`, панель ввода `claude-input`, сторож внимания демона и следование herdr за диалогами агентов работают. Добавлены оболочка bash с ble.sh, fzf, atuin, television и zoxide на согласованных клавишах и плагин herdr `keys-help` — подсказка горячих клавиш по контексту в нижней панели ([`docs/keys-help.md`](docs/keys-help.md)). Остаётся закрыть двенадцать активных изменений OpenSpec: архивацию держат только проверки пользователя и одна перезагрузка. Конфиг сессии и поведение остального не меняются.

### Открытые вопросы к пользователю

- [`herdr-keys-help`](openspec/changes/herdr-keys-help/tasks.md), 9.3 и таблица регрессий протокола kitty: после перезапуска клиента herdr (сервер ещё на сборке `duty-v0.9.5.14+ru-layout-chords`, установлен `duty-v0.9.5.15`) Alt+R, Alt+T, Alt+H в оболочке открывают atuin, tv и fzf с их таблицами в нижней панели; Esc и `i` меняют таблицу режима ble.sh; Alt+F, Alt+D, Alt+↑, Ctrl+Alt+T работают; Ctrl+Alt+Shift+/ и Ctrl+Alt+R срабатывают в русской раскладке; панель `claude-input` печатает как прежде. После подтверждения — архивация (шаг 1).
- Панель ввода `claude-input`: стрелки вверх и вниз листают историю ввода Claude Code (после переоткрытия панели Ctrl+Alt+R); выбор пункта свободного ввода в диалоге не уводит с workspace диалога (форк herdr с `duty-v0.9.5.14`).
- Neovim: `gq` не переносит строки, потому что `formatexpr` отдан conform.nvim с prettier (`--prose-wrap preserve`), работает только `gw`. Варианты: `formatexpr=""` с `textwidth` для markdown и текста в ftplugin; prettier с `--prose-wrap always --print-width 80`; `formatexpr=""` глобально. Решение не принято.
- Перенос ble.sh с ручной копии `~/.local/share/blesh` на пакет AUR `blesh-git` с записью в `docs/host-state.md` и таблицы `docs/package-sources*.md`; заодно `pacman -D --asexplicit fzf`, `atuin import auto`, `HISTSIZE`/`HISTFILESIZE`/`histappend` в `dot_bashrc`. Пользователь не поручал, предложено.
- Перезагрузка: пункт 4.1 [`session-instances`](openspec/changes/session-instances/tasks.md) и пункт 3.4 [`session-windows-transient`](openspec/changes/session-windows-transient/tasks.md) (действия до неё — в тексте задач). После входа агент сверяет журнал демона и `hyprctl clients -j`, затем архивирует цепочку. Той же перезагрузкой проверяются `snapshot-stale-rects` и `snapshot-stale-section`: окна `work` встают по `thirds-split`, при подъёме `surf` по Super+V Chrome AI слева и Chrome AI2 справа.
- [`enter-backspace-keys`](openspec/changes/enter-backspace-keys/tasks.md), 5.5: при непустой истории уведомлений Shift+Super+Backspace — история пуста, число на плитке исчезло.
- [`toggle-windows`](openspec/changes/toggle-windows/tasks.md), 4.2: при спрятанном Telegram приходит настоящее сообщение, левый клик по карточке — окно с топиком на текущем столе, окна `special:pool` не мелькают заметно. Пункт 4.3: клик по значку Telegram в трее при спрятанном окне — окно 1500×1500 по центру с фокусом.
- [`notifications-top-stack`](openspec/changes/notifications-top-stack/tasks.md), 4.1: оценить вид столбика уведомлений.
- Проверка кликами значков туннелей в трее (изменение `tunnel-tray-autostart`, архив): левый клик по верхнему значку (`amn0`) открывает справа от колонки окно со строками «Endpoint», «Handshake», «Элементов zones» и журналом, клик вне окна закрывает его; правый клик по значку `axata` открывает меню «Отключить», «Настройки». Действия меню без нужды не выбирать: через туннели работают агенты.
- Проверка кликами выбора страны (изменение `tunnel-country-link`, архив): правый клик по значку `amn0` → «Страна туннеля…» открывает сетку стран с выделенной текущей (Франция); выбор другой страны перезапускает `amn0` (обрыв на 10–20 с), после чего в окне сведений строки «Страна» и «Выход» совпадают.
- Проверка состояния «поднят, связи нет» настоящим обрывом (изменение `tunnel-country-link`, архив): `sudo -A -p 'Проверка связи amn0' nft 'add table inet amntest; add chain inet amntest out { type filter hook output priority 0; }; add rule inet amntest out ip daddr <адрес Endpoint amn0> drop'` — значок `amn0` через 10–15 с оранжевый, подсказка называет «Handshake did not complete … (try 3)»; `sudo -A -p 'Конец проверки связи amn0' nft delete table inet amntest` — снова зелёный. Трафик через `amn0` на время проверки прерывается, поэтому её делает пользователь, когда через туннель никто не работает. Для `axata` проверки нет: профиль без `ping-restart` (решение пользователя, `docs/amnezia-split-tunnel.md`).
- Проверка перезагрузкой автозапуска туннелей (изменение `tunnel-tray-autostart`, архив) и чистого старта herdr (изменение `herdr-prestart`, архив): после входа оба значка туннелей зелёные, в выводе `journalctl -b -o short-monotonic -u awg-quick@amn0 -u axata-vpn -u tunnels-before-login -u greetd | grep -E 'Starting|Finished|Started'` строки `Finished` у `awg-quick@amn0` и `axata-vpn` стоят раньше `Started` у `greetd`; `journalctl --user -b -u herdr-prestart` содержит итог `claude update`, `herdr update`, интеграции и строку о переименовании `session.json`, окно herdr показывает одно пространство в `~/work/telecom/axata/monorepo-ocp`, `pgrep -x claude` пусто. Итог по туннелям — в `docs/amnezia-split-tunnel.md`, раздел «Автозапуск туннелей».
- Отправка черновиков из `docs/upstream/` (отчёты Hyprland и Chromium о родителе окна): срок, на который решение было отложено, истёк 23.10.2026, вопрос задаётся снова ([`hyprland-window-parent.md`](docs/open-questions/hyprland-window-parent.md)).

### Где остановились

- Деревья chezmoi (`main`, `3ce734d`), `~/work/pets/duty-herdr` (`duty`, `bea0f9d2`, выпуск `duty-v0.9.5.15` на GitHub и в `~/.local/bin/herdr`) и `~/work/pets/workspaced` (`master`, `ca1db63`) чисты, всё отправлено в `origin`. Сервер herdr не перезапускался: он работает на сборке с той же правкой русской раскладки, новый бинарник подхватится при перезапуске.
- Оболочка: `dot_blerc` и `dot_bashrc` — fzf (Alt+H история, Alt+F файлы, Alt+D cd; штатные C-t/C-r/M-c сняты), atuin (Alt+R, Alt+↑, собственные привязки выключены), television (Alt+T, Ctrl+Alt+T; его `bind -x` на C-t/C-r перебиты после `tv init`), zoxide; ble.sh оставлен на Ctrl+R/S/T/H/F/], Ctrl+Z, ↑. Таблица сверена `ble-bind -P`. В vi-режимах ble.sh привязок с Alt нет: незанятое Alt+клавиша — это Esc и клавиша.
- `keys-help`: плагин зарегистрирован (`herdr plugin list`), ссылка `~/.config/herdr/keys-help/view.toml` стоит, протокол kitty в wezterm и рамки herdr только разделителями применены, хук `SessionStart` печатает неизвестные программы; 213 тестов плагина зелёные, ревью high — 10 находок исправлено ([`report.md`](/home/mne/.local/state/duty/dotfiles/results/keys-help/report.md), запись [`0010`](docs/decisions/0010-keys-help-herdr-plugin.md)). Открыты 9.3 и 11.1.
- Hyprland 0.57.1: `render.cm_auto_hdr = 0` — полноэкранный Chromium больше не переводит монитор в HDR (картинка подтверждена). Условие пересмотра [`hyprland-blur-variants.md`](docs/open-questions/hyprland-blur-variants.md) наступило: 0.57 в pacman и установлен.
- Форк herdr: тест `federated_client_starts_without_local_and_survives_its_restart` падал из-за дефекта теста (команда с кавычками после обрывка ввода при переподключении), исправлен коммитом в `duty`; полный nextest 4437/4437.
- Кэш пакетов yazi (`~/.cache/yazi/packages`) был повреждён и ронял `ya pkg install` при `chezmoi apply`; пересоздан, плагины стоят.
- OpenSpec: 12 активных изменений, каждое проходит `openspec validate <имя> --strict`; `openspec validate --specs` падает на длинных требованиях, им не пользоваться. Порядок архивации цепочки: `session-instances` → `live-layout` → `work-area-center` → `askpass-only-quickshell` → `sticky-chains` → `chains-sticky` → `session-windows-transient` → `toggle-windows` → `shared-app-chain` → `enter-backspace-keys`; `notifications-top-stack` и `herdr-keys-help` вне цепочки. Живые проверки ydotool прошли ([`report.md`](/home/mne/.local/state/duty/dotfiles/results/openspec-reconcile/report.md)).
- VoxType: `initial_prompt` переписана короче со всеми латинскими названиями (wezterm, atuin, ble.sh, herdr, neovide, neovim, prettier). `claude-input`: подсказка диалога в правом окне (1:4, не меньше 20 столбцов), кнопка «Next» в множественном выборе, история ввода стрелками; детектор herdr держит `blocked` в поле свободного ввода ([`docs/claude-input.md`](docs/claude-input.md)).

### Следующие шаги

1. После подтверждения 9.3: отметить 9.3 и 11.1 в `tasks.md`, `openspec validate herdr-keys-help --strict`, `openspec archive herdr-keys-help -y`, коммит и push.
2. По решению пользователя о `gq`: субагент на Sonnet правит `dot_config/nvim` (ftplugin или conform), `chezmoi apply`, проверка `gq}` на абзаце markdown в Neovide.
3. По решению о ble.sh из AUR: `paru`/`pacman` `blesh-git`, `dot_bashrc` на `/usr/share/blesh/ble.sh`, удалить ручную копию, `docs/host-state.md` и `docs/package-sources*.md`; тем же изменением `HISTSIZE`, `atuin import auto`.
4. Варианты размытия панели ([`hyprland-blur-variants.md`](docs/open-questions/hyprland-blur-variants.md)): условие наступило, Hyprland 0.57.1 — подобрать по плану файла, вопрос закрыть.
5. После перезагрузки по вопросам снимка: сверить журнал демона и `hyprctl clients -j`, плитку стола 1 (`qs -c panel ipc call workspaces row 1`), `conceal_vrr_caps = Y` (`system/modprobe.d/nvidia-vrr.sh status`); дописать `docs/host-state.md`, отметить 4.1 и 5.4 `session-instances`; архивировать цепочку в порядке из «Где остановились», `notifications-top-stack` — после оценки вида; ссылки в `docs/window-model.md` перевести на архивные.
6. Дефекты демона workspaced: поднятие workspace и `workspaced arrange` при полноэкранном окне дают ошибку композитора «Window is fullscreen» — пропускать такие окна; правка геометрии ячеек шаблона при работающем демоне раскладку не пересобирает (`keep_layout`) — учесть шаблон (`design.md` изменения `snapshot-stale-rects`); комментарий в `daemon.rs` к записям без workspace — D16 вместо D17.
7. Агент polkit на Quickshell — отдельное изменение по плану D5 из `openspec/changes/askpass-only-quickshell/design.md`.
8. По желанию пользователя: понизить до info предупреждение демона «исполняемый файл команды … не найден» для процессов из `fedora-box` (`proc_info`, `src/daemon.rs`).

### Как проверить

```bash
openspec list                              # 12 активных изменений
for c in $(openspec list --json | jq -r '.changes[].name'); do openspec validate $c --strict; done
herdr --version                            # duty-v0.9.5.15
herdr plugin list | rg keys-help           # quiet-lab.keys-help enabled
ls -l ~/.config/herdr/keys-help/view.toml  # ссылка в источник chezmoi
cd ~/.config/herdr/plugins/keys-help && cargo test --locked 2>&1 | tail -3   # 213 passed
script -qec 'bash -ic "ble-bind -m vi_imap -P; ble-bind -m vi_nmap -P"' /dev/null | rg -e 'M-h|M-f|M-d|M-r|M-up|M-t|C-M-t|C-t|C-r'
SIG=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1); HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl getoption render:cm_auto_hdr   # int: 0
cd ~/.config/nvim/local/ru-layout && bash tests/run-all.sh   # тесты ru-layout
systemctl --user is-active workspaced.service ydotool.service
workspaced check && workspaced status --json | jq -c '.desktops | to_entries | map({(.key): [.value.active, [.value.workspaces[].name]]}) | add'
HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl clients -j | jq -c '.[] | {class, ws: .workspace.name, at, size, fullscreen}'
cd ~/work/pets/workspaced && cargo test 2>&1 | tail -3   # 209 passed
chezmoi status && git status -sb          # только строка R link-herdr-keys-help.sh (сценарий run_after)
```

Тесты `claude-input`: `cd dot_config/nvim/local/claude-input && nvim --headless --clean -u NONE -l tests/switch_spec.lua && nvim --headless --clean -u NONE -l tests/dialog_spec.lua` — ALL OK ([`docs/claude-input.md`](docs/claude-input.md)).

### Что пробовали и отвергли

- Прямой `source /usr/share/fzf/key-bindings.bash`: он безусловно переназначает Ctrl+Z на смену keymap readline; взят `ble-import contrib/integration/fzf-key-bindings`, где эти `bind` глушатся. Снимать `bind -x` от `tv init` через `bind -r`: ble.sh удалял и свои C-t/C-r — вместо этого `ble-bind -f` после `tv init`.
- Для HDR в полном экране: 10-битный режим монитора и флаги Chromium отвергнуты в пользу `cm_auto_hdr = 0` — HDR-контент в браузере не смотрят, поддержка протокола цвета в Hyprland 0.57 не завершена.
- Снимать и снова ставить fullscreen или `bring_to_top` для полноэкранного окна ([`design.md`](openspec/changes/archive/2026-10-23-fullscreen-raise/design.md)); считать прямоугольник окна из снимка устаревшим по несовпадению с ячейкой и `moved` ([`design.md`](openspec/changes/archive/2026-10-24-snapshot-stale-rects/design.md)).
- Таймеры вместо событий ([`0007`](docs/decisions/0007-no-timers.md)); правило окна `focus_on_activate = false` для Telegram; `hyprland-git` из AUR ради размытия; запасной pinentry у окна пароля.
- `openspec validate --specs` как общая проверка: падает на длинных требованиях.

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
