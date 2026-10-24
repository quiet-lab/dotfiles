# Дела репозитория dotfiles

## Текущая работа

Снимок на 2026-10-24. Файл хранится в git, но в `$HOME` не попадает: он исключён в `.chezmoiignore`.

### Цель

Сессия Hyprland с демоном workspaced и панелью Quickshell доведена до нынешнего вида: четыре стола, `work` на шаблоне `thirds-split` в режиме `home`, `surf` на `overlay`, окно-переключатель Telegram, размытие и прозрачность окон подобраны. Серия изменений модели окон по [`docs/window-model.md`](docs/window-model.md) реализована целиком; ждут закрытия семь изменений OpenSpec (`session-instances`, `live-layout`, `work-area-center`, `askpass-only-quickshell`, `sticky-chains`, `chains-sticky`, `session-windows-transient`) и одна проверка перезагрузкой. Конфиг сессии и поведение остального не меняются.

### Открытые вопросы к пользователю

- Проверка перезагрузкой изменений `snapshot-stale-rects` и `snapshot-stale-section` (предложена 24.10.2026, пользователь делает её, когда удобно): снимок сессии по-прежнему от 17.10.2026, после входа окна `work` должны встать по `thirds-split` (Chromium слева вверху, Chrome слева внизу, herdr в центре, neovide справа), а при поднятии `surf` по Super+V Chrome AI слева и Chrome AI2 справа. Той же перезагрузкой закрывается пункт 4.1 `session-instances` (ниже).
- Проверка перезагрузкой изменения `session-instances` (пункт 4.1 его [`tasks.md`](openspec/changes/session-instances/tasks.md)); отложена пользователем 29.09.2026, от неё зависит архивация всех семи активных изменений. Перед ней открыть второе окно Chromium в `work` и второй neovide, нажать Ctrl+Super+S, затем S, перезагрузиться — после входа состояние должно вернуться с экземплярами и общими окнами. Итог дописать в `docs/host-state.md` (пункт 5.4 того же `tasks.md`).
- Отправка черновиков из `docs/upstream/` (отчёты Hyprland и Chromium о родителе окна): срок, на который пользователь отложил решение, истёк 23.10.2026, вопрос задаётся снова ([`hyprland-window-parent.md`](docs/open-questions/hyprland-window-parent.md)).

### Где остановились

- Демон на коммите `00bbb71` (`~/work/pets/workspaced`, `master`, 188 тестов), служба `workspaced.service` работает на этом бинарнике. Сверх снимка от 29.09: расстановка Ctrl+Super+Пробел возвращает раскладку к конфигу ([`tasks.md`](openspec/changes/archive/2026-10-22-arrange-restores-config/tasks.md)), режим `home` и шаблон `thirds-split` у `work` ([`tasks.md`](openspec/changes/archive/2026-10-23-home-mode-layout/tasks.md)), окно-переключатель прячется при потере фокуса ([`tasks.md`](openspec/changes/archive/2026-10-23-toggle-hide-on-blur/tasks.md)), ключ `desktops = 4` ([`tasks.md`](openspec/changes/archive/2026-10-24-four-desktops/tasks.md)).
- Полноэкранное окно, выбранное клавишей, поверх окон своего стола: окна с признаком `allowedOverFullscreen` демон опускает диспетчером `alter_zorder bottom`, полноэкранный режим не трогает ([`tasks.md`](openspec/changes/archive/2026-10-23-fullscreen-raise/tasks.md)); проверено пользователем 24.10.2026 на видео в Яндекс.Браузере.
- Раскладка снимка сессии считается устаревшей и собирается из конфига, если изменились ячейки шаблона (снимок пишет `grid`) или раздел workspace (снимок пишет `homes` и `homes_main`); вместе с ней не действуют прямоугольники окон этого workspace, прямоугольники других workspace у общего окна остаются ([`tasks.md`](openspec/changes/archive/2026-10-24-snapshot-stale-rects/tasks.md), [`tasks.md`](openspec/changes/archive/2026-10-24-snapshot-stale-section/tasks.md)). Проверено перезапуском демона и циклом Super+V; перезагрузкой — вопрос выше.
- Панель: четыре плитки столов одной высоты 82 px с табами на 1462…1820 px, правая колонка вровень (уведомления 1462, трей 1508 высотой 266, раскладка 1784), средняя группа опущена (датчики 704, сеть 814, диски 931, избранное 1176); вид проверен пользователем 24.10.2026. Заливка плиток 0.8 (`Theme.tileBg`).
- Размытие и прозрачность в `hyprland.lua`: `blur size = 1, passes = 4`, `vibrancy` по умолчанию; обычные окна в фокусе 0.8 с размытием, без фокуса 0.6 без размытия; браузеры в фокусе 1.0, без фокуса 0.6, без размытия; плееры, игры и модальные окна непрозрачны. Варианты размытия ждут Hyprland 0.57 в pacman ([`hyprland-blur-variants.md`](docs/open-questions/hyprland-blur-variants.md); сейчас в репозитории 0.56.2).
- Super+Shift+Пробел намеренно свободен (решение пользователя 22.10.2026).
- Окно пароля sudo — только Quickshell ([`0008`](docs/decisions/0008-askpass-quickshell-only.md)); раскладка после диктовки VoxType возвращается перехватом `post_output_command` ([`hyprland-keymap-group-after-virtual-keyboard.md`](docs/open-questions/hyprland-keymap-group-after-virtual-keyboard.md)); гонка модуля Hyprland в Quickshell при старте обойдена в панели (`tiles/Workspaces.qml`, повторный запрос списка окон), подтверждение даст следующий старт сессии.
- Рабочие деревья chezmoi (`main`) и `~/work/pets/workspaced` (`master`) чисты, всё отправлено в `origin`. Фоновые оболочки с тестами `~/work/telecom/axata` принадлежат другой сессии и не трогались.

### Следующие шаги

1. После перезагрузки пользователя снять итог: окна `work` и `surf` по конфигу (`hyprctl clients -j`, журнал демона — строки «собирается заново из конфига»), пункт 4.1 `session-instances` и 3.4 `session-windows-transient`, плитка стола 1 сразу с значками herdr и neovide (`qs -c panel ipc call workspaces row 1`), `conceal_vrr_caps` (команда `status` ниже). Итог — в `docs/host-state.md`, отметить 4.1 и 5.4.
2. Архивировать по порядку, после каждого — `openspec validate --specs`: `session-instances` → `live-layout` (5.1–5.2) → `work-area-center` (6.1; после него проверить в `openspec/specs/hyprland-binds/spec.md` строки Shift+Super+/ и Alt+Super+Enter) → `askpass-only-quickshell` (6.1) → `sticky-chains` (6.3) → `chains-sticky` (5.2) → `session-windows-transient` (4.1). Перед каждой архивацией сверить дельты с нынешним текстом спецификаций: поздние изменения (`four-desktops`, `fullscreen-raise`, снимок) правили те же требования. Ссылки в `docs/window-model.md` перевести на архивные.
3. Проверки 3.3 и 3.5 `session-windows-transient` командами (3.3 поднимает `surf` и меняет стол пользователя — делать, предупредив его).
4. Дефект демона: поднятие workspace и `workspaced arrange` при полноэкранном окне в нём завершаются ошибкой композитора «Window is fullscreen» (демон двигает такое окно), окна при этом расставляются верно — пропускать полноэкранные окна при расстановке или снимать ошибку; найден 23.10.2026, не исправлялся.
5. Дефект демона: правка геометрии ячеек шаблона при работающем демоне раскладку не пересобирает (`keep_layout` сравнивает только разделы workspace), новая геометрия действует после перезапуска — учесть шаблон в сравнении; записан в `design.md` изменения `snapshot-stale-rects`.
6. Комментарии в демоне: к запуску записей без workspace ссылка на D16 вместо D17 (`session-instances`, пункт 5.7) — при следующей правке `daemon.rs`.
7. Агент polkit на Quickshell (`Quickshell.Services.Polkit`) — отдельное изменение по плану D5 из `openspec/changes/askpass-only-quickshell/design.md`.
8. По желанию пользователя (предложено 29.09.2026, ответа нет): понизить до info предупреждение демона «исполняемый файл команды … не найден» для процессов из контейнера distrobox (`proc_info`, `src/daemon.rs`); сейчас оно повторяется при каждом захвате окна браузера из `fedora-box`.

### Как проверить

```bash
openspec list                              # активны: chains-sticky, session-instances, live-layout, sticky-chains, askpass-only-quickshell, work-area-center, session-windows-transient
openspec validate --specs                  # 20 passed
systemctl --user is-active workspaced.service quickshell-panel.service voxtype.service voxtype-mute-others.service
workspaced check && workspaced status --json | jq -c '.desktops | to_entries | map({(.key): [.value.active, [.value.workspaces[].name]]}) | add'   # столы 1…4
journalctl --user -u workspaced.service -b | rg 'собирается заново из конфига|не действуют'   # раскладка снимка по конфигу
SIG=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1); HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl clients -j | jq -c '.[] | {class, ws: .workspace.name, at, size, fullscreen, allowedOverFullscreen}'
qs -c panel ipc call workspaces desktops; qs -c panel ipc call workspaces row 1
cd ~/work/pets/workspaced && cargo test 2>&1 | tail -3   # 188 passed
env -u SUDO_ASKPASS sudo -A -p 'Проверка окна пароля' true   # окно Quickshell, Escape даёт код 1
system/modprobe.d/nvidia-vrr.sh status    # после перезагрузки ожидается conceal_vrr_caps = Y
chezmoi status && git status -sb          # расхождений и незакоммиченного быть не должно
```

### Что пробовали и отвергли

- Снимать и снова ставить fullscreen или `bring_to_top` для полноэкранного окна: браузер выходит из полноэкранного видео, `bring_to_top` ставит признак самому окну, соседям не снимает; `misc:on_focus_under_fullscreen` касается только неплавающих окон ([`design.md`](openspec/changes/archive/2026-10-23-fullscreen-raise/design.md)).
- Считать прямоугольник окна из снимка устаревшим, если он не совпадает ни с ячейкой, ни с `moved`: второй экземпляр, сдвинутый мышью, законно стоит вне обоих ([`design.md`](openspec/changes/archive/2026-10-24-snapshot-stale-rects/design.md)); устаревание раскладки по правке `chain` и `mode` — раскладка от них не зависит.
- Размытие `size 9, passes 1` двоит картинку, большие шаги вообще — заменено малым шагом в несколько проходов; `hyprland-git` из AUR ради вариантов размытия пользователь отверг.
- Таймеры вместо событий — пользователь велел обходиться событиями ([`0007`](docs/decisions/0007-no-timers.md)); правило окна `focus_on_activate = false` для Telegram отключило бы переход к топику по клику на уведомление; Ctrl+Enter как клавиша «не беспокоить» нужна приложениям.
- Запускать общее окно при восстановлении сессии вторым экземпляром там, где его приложение не описано в конфиге: общие окна остаются общими (решение пользователя 29.09.2026); запасной pinentry у окна пароля отвергнут 23.09.2026.

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
