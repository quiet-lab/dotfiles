# Design: Рабочий конфиг Hyprland под chezmoi

## Context

Мотивация в proposal.md (Why), требования в specs/. Состояние системы на 2026-09-10:

- Hyprland 0.56.2 с Lua-API; пример конфига `/usr/share/hypr/hyprland.lua`, заглушки API в `/usr/share/hypr/stubs/hl.meta.lua` (события `hyprland.start`, `hyprland.shutdown`, `config.reloaded`; `hl.bind`, `hl.window_rule`, `hl.exec_cmd`, `hl.env`, `hl.on`). Пробный `~/.config/hypr/hyprland.lua` проверен на NVIDIA: монитор, `hl.env`, `kb_file`, эффекты, параметр пружины `dampening`.
- Бинарник Hyprland 0.56.2 импортирует в systemd пользователя и D-Bus переменные `DISPLAY`, `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, `XDG_CURRENT_DESKTOP`, но `graphical-session.target` не активирует: встроенная интеграция, описанная в вики 26.08.2026, в эту версию ещё не вошла (строк `graphical-session` в бинарнике нет). Юниты `voxtype.service`, `hyprpolkitagent.service`, `dunst.service` объявляют `PartOf=graphical-session.target`, первые два ещё и `WantedBy=graphical-session.target`.
- lightdm 1.33 читает `/usr/share/wayland-sessions` (умолчание `sessions-directory`), в бинарнике есть обработка Wayland-сессий (`wayland_session_set_vt`, `XDG_SESSION_TYPE`). Пакет hyprland установил `hyprland.desktop` (`Exec=/usr/bin/start-hyprland`) и `hyprland-uwsm.desktop`. `~/.dmrc` хранит выбранную сессию. Обёртка `/etc/lightdm/Xsession` запускает `$SHELL --login`, благодаря чему X11-сессия получает `PATH` с `~/.local/bin` из `~/.profile`; применяется ли обёртка к Wayland-сессиям, не проверено.
- В `~/.local/bin` лежат симлинки на собранные из исходников `wezterm`, `wezterm-gui`, `eww`, `eww-daemon`. Переменные `QT_QPA_PLATFORMTHEME=qt6ct` и `LESSHISTFILE` X11-сессия берёт из `~/.config/openbox/environment` и `~/.xprofile`, которые Hyprland не читает.
- rofi 2.0.0 собран с Wayland; nm-applet 1.36 собран с libappindicator (StatusNotifier); dunst работает через layer-shell; voxtype 0.7.5 с конфигом из chezmoi, wtype 0.4 установлен.
- Скрипты `dot_scripts/` громкости (amixer) и яркости (brightnessctl) от сервера отображения не зависят; скриншоты используют scrot и xclip, снимки в `~/Pictures/Screenshots`.
- VPN: у `axata` пароль хранится в NetworkManager (`password-flags=0`), у `kozloff-de` `connection.autoconnect no`. В Openbox поднятие `axata` уже сделано в `autostart.sh` блоком с ожиданием состояния `connected` до 30 с.
- Обои: `~/.config/nitrogen/bg-saved.cfg` под chezmoi, файл `~/.wallpapers/mechanical/okita-souji_FHD.jpg`, режим zoom-fill, подложка чёрная.

## Goals / Non-Goals

**Goals:**

- Один управляемый файл `hyprland.lua`, который можно читать сверху вниз: монитор, окружение, ввод, вид, правила, привязки, автозапуск; переезд привязок без изменения привычек.
- Сессия, пригодная для повседневной работы без панели: столы, окна, буфер обмена, скриншоты, блокировка, VPN, голосовой ввод.
- Возможность вернуться в Openbox одним выбором в greeter в любой момент.

**Non-Goals:**

- Панель и плитки, Lua-раскладка зон, удаление Openbox и eww, uwsm, автоблокировка по бездействию, настройка порталов для демонстрации экрана сверх установки пакета, VA-API в основном профиле Firefox.

## Decisions

**D1. Один файл `hyprland.lua` с разделами, без разбиения на модули.**
Конфиг умещается в несколько сотен строк; разбиение через `dofile` усложнило бы `hyprctl reload` и поиск. Разделы отделяются заголовками-комментариями, как в пробном файле. Альтернатива «каталог `conf.d` с `dofile`» отложена до появления Lua-раскладки зон, которой понадобится собственный файл.

**D2. Скрипты сессии в `dot_config/hypr/scripts/` с префиксом `executable_`.**
Скрипты Wayland для скриншотов (`screenshot-screen`, `screenshot-countdown`, `screenshot-selection`), поднятия VPN (`vpn-up`) и меню буфера обмена (`clipboard-menu`) лежат рядом с конфигом, как скрипты виджетов eww лежат в `widgets/<name>/scripts/`. В конфиге пути пишутся без префикса (`~/.config/hypr/scripts/vpn-up`). `dot_scripts/` не меняется: те же имена в нём означают версии для X11, а обе сессии должны работать параллельно. Альтернатива «добавить в скрипты X11 ветку по `WAYLAND_DISPLAY`» отвергнута: скрипты Openbox взяты из чужих dotfiles и переписывать их ради второй ветки дороже, чем написать короткие новые.

**D3. `graphical-session.target` поднимает собственный `hyprland-session.target`.**
В `dot_config/systemd/user/hyprland-session.target` описывается цель с `BindsTo=graphical-session.target` и `Before=graphical-session.target` (подход из прежней версии вики). В конфиге `hl.on("hyprland.start")` выполняет `systemctl --user start hyprland-session.target`, а `hl.on("hyprland.shutdown")` — `systemctl --user stop graphical-session.target`. Тогда `voxtype.service` и `hyprpolkitagent.service` включаются через `systemctl --user enable` и стартуют юнитами, `dunst` активируется по D-Bus, а в X11-сессии Openbox цель не поднимается и эти юниты не запускаются. Когда обновление Hyprland принесёт встроенную интеграцию, цель удаляется командой `systemctl --user revert hyprland-session.target` и обработчики из конфига убираются; это фиксируется в задачах как условие при обновлении. Альтернатива «всё через `hl.exec_cmd`» отвергнута: юниты с `PartOf=graphical-session.target` всё равно ждут цель, а без неё `hyprpolkitagent.service` и `voxtype.service` пришлось бы дублировать процессами.

**D4. Остальной автозапуск через `hl.on("hyprland.start", …)` и `hl.exec_cmd`.**
nm-applet (`--indicator`), два наблюдателя `wl-paste --watch cliphist store` (текст и изображения), `vpn-up`, wezterm и firefox запускаются из обработчика события `hyprland.start`, который срабатывает один раз при старте композитора и не срабатывает при `hyprctl reload`. Защита от дублей в обработчике не нужна. hyprpaper и hypridle, как выяснилось при установке, поставляют пользовательские юниты с `WantedBy=graphical-session.target`, поэтому включаются через `systemctl --user enable` вместе с voxtype и hyprpolkitagent и стартуют через цель из D3.

**D5. Окна плавающие по умолчанию через правило `hl.window_rule({ match = { class = ".*" }, float = true })`.**
Раскладка `dwindle` остаётся включённой на случай перевода окна в мозаику привязкой Super+Shift+V (`hl.dsp.window.float({ action = "toggle" })`), но новые окна открываются плавающими, как в Openbox. Половины рабочей области по Super+Shift+стрелки задаются функцией Lua, которая берёт размер активного монитора и зарезервированные зоны (`hl.get_active_monitor()`), вычисляет геометрию с отступами 10 px и вызывает диспетчеры `window.resize` и `window.move` с точными значениями (имена и параметры уточняются по `hl.meta.lua` при реализации). Альтернатива «фиксированные числа, как в rc.xml» отвергнута: без панели рабочая область другая, а с панелью Quickshell снова изменится.

**D6. Сворачивание через специальный рабочий стол.**
Super+Z переносит активное окно на `special:hidden` без перехода за ним; Super+Shift+Z переключает показ специального стола (`hl.dsp.workspace.toggle_special("hidden")`), откуда окно возвращается на стол через Super+Shift+N. Два сочетания вместо одного: после скрытия окна фокус уходит к следующему окну, и повторное Super+Z спрятало бы уже его. Ближайшая замена Iconify из Openbox; Hyprland сворачивания не имеет.

**D7. Переменные окружения X11-сессии переезжают в `hl.env`.**
`QT_QPA_PLATFORMTHEME=qt6ct`, `LESSHISTFILE=/dev/null`, четыре переменные NVIDIA и `MOZ_DISABLE_RDD_SANDBOX=1` задаются через `hl.env` и действуют на всё, что запускает композитор. `PATH` дополняется `~/.local/bin` и `~/.bun/bin` тоже через `hl.env`, поскольку неизвестно, применяет ли lightdm login-оболочку к Wayland-сессии; проверка в задачах. Файлы `~/.config/openbox/environment` и `~/.xprofile` не меняются.

**D8. Буфер обмена: cliphist с меню через rofi.**
`clipboard-menu`: `cliphist list | rofi -dmenu | cliphist decode | wl-copy`. rofi запускается в режиме Wayland без отдельного конфига, используется единый `dot_config/rofi/config.rasi`. clipcat в сессии Hyprland не запускается.

**D9. Блокировка: hypridle слушает logind, hyprlock рисует экран.**
`hypridle.conf` содержит только `general { lock_cmd = pidof hyprlock || hyprlock }` и `before_sleep_cmd` не задаёт: пользователь спящим режимом не пользуется, таймаутов бездействия нет. `hyprlock.conf` минимальный: фон с тем же файлом обоев, поле пароля. Super+L вызывает `loginctl lock-session`, как в Openbox, так что привычка не меняется.

**D10. Скриншоты: grim, slurp, wl-copy, dunstify.**
Три скрипта повторяют поведение X11-версий: тот же каталог `~/Pictures/Screenshots`, то же именование по дате, копия в буфер через `wl-copy`, уведомление dunstify. Обратный отсчёт делается `sleep`; выделение области — `slurp`. Скриншоты через портал не используются: grim работает напрямую с композитором.

**D13. Прозрачность и размытие переносятся из picom правилами окон.**
Значения picom: непрозрачность 0.9 в фокусе и 0.7 без фокуса, 1.0 для полноэкранных и служебных окон, размытие dual_kawase силой 1.3 только у терминалов и neovide в фокусе, браузеры и видео в фокусе непрозрачные, тень радиусом 40 с плотностью 0.5 и смещением −27, скругление 8. В Hyprland это `decoration.active_opacity`, `inactive_opacity`, `fullscreen_opacity`, `shadow` и `blur` (size 3, passes 1 как лёгкое размытие) плюс четыре правила окон, применяемые сверху вниз: `no_blur` для всех, `no_blur = false` для терминалов с `focus = true`, `opacity = "1.0 override"` для браузеров, видео и игр в фокусе, то же для модальных окон (`modal = true`). Правило по заголовку консольных программ из picom не нужно: класс wezterm покрывает их. Решение принято 2026-09-10 после первого входа по замечанию пользователя, что окна в фокусе непрозрачные. Тень после первых дней в сессии изменена по просьбе пользователя: дальность 10 вместо 40 и смещение 7 px вниз и вправо вместо −27 влево и вверх.

**D11. Журнал Hyprland остаётся подробным (`debug.disable_logs = false`) на переходный период.**
Без него журнал не содержит окон и Xwayland, а первые недели работы принесут вопросы. Файл лежит в `$XDG_RUNTIME_DIR/hypr/<сигнатура>/hyprland.log` на tmpfs и очищается при перезагрузке.

**D12. Обои — hyprpaper с файлом из `bg-saved.cfg`.**
`hyprpaper.conf` указывает тот же файл `~/.wallpapers/mechanical/okita-souji_FHD.jpg` для DP-2 в режиме заполнения. Файл обоев под chezmoi не берётся (двоичный, 2 МБ), путь один и тот же для обеих сессий.

**D14. Параметр драйвера `nvidia_modeset.conceal_vrr_caps=1` в `/etc/modprobe.d/nvidia-vrr.conf`.**
Под KMS при 3840×2160@120 (и @98) картинка была темнее, а шрифты заметно хуже, чем в X11 при том же канале RGB 8 бит; при 60 Гц (RGB 10 бит) разницы не было. По исходникам nvkms 610.57 nvidia-drm при каждом modeset безусловно разрешает Adaptive-Sync (`allowAdaptiveSync = ALL` в `nvkms-kapi.c`), и nvkms переводит монитор Philips 558M1R в этот режим по биту `MSA_TIMING_PAR_IGNORED` в DPCD, независимо от `VRR_ENABLED`; X-драйвер делает это только с опцией `AllowGSYNCCompatible`. Панель в режиме Adaptive-Sync меняет гамму. Параметр скрывает от драйвера возможности VRR монитора (`vrr_capable` в DRM равен 0), и после перезагрузки 2026-09-10 120 и 60 Гц стали неотличимы. Файл лежит в `/etc`, под chezmoi не берётся (источник управляет только `$HOME`), поэтому его содержимое и назначение зафиксированы здесь и в спецификации. Цена: VRR в сессии недоступен вовсе, для игр с переменной частотой параметр придётся убирать или искать другой путь. Отвергнутые кандидаты: `render.cm_enabled=false`, `debug_force_color_space=1`, `dithering mode=off`, смена композитора (weston давал ту же картинку).

**D15. Выбор файла через портал делает yazi в окне wezterm.**
Бэкенд `xdg-desktop-portal-termfilechooser` 1.4.3 (AUR, форк hunkyburrito) реализует интерфейс FileChooser и запускает терминальный файловый менеджер; выбранные пути возвращаются приложению через `--chooser-file` yazi. Под chezmoi два новых файла: `dot_config/xdg-desktop-portal/hyprland-portals.conf` (файл в `~/.config` имеет приоритет над пакетным: `default=hyprland;gtk`, `FileChooser=termfilechooser`) и `dot_config/xdg-desktop-portal-termfilechooser/config` (обёртка yazi из пакета, `TERMCMD=wezterm start --always-new-process --class termfilechooser --`, `create_help_file=1`, `open_mode` и `save_mode` равны `suggested`). Сохранение устроено так: портал создаёт в предложенном приложением каталоге файл с предложенным именем и инструкцией внутри, yazi открывается с курсором на нём; пользователь при необходимости переносит (x, p) или переименовывает (r) файл и «открывает» его клавишей Enter, после чего приложение перезаписывает файл; выход по q отменяет сохранение, и файл удаляется. Без файла-подсказки (`create_help_file=0`, как было настроено сначала) при сохранении выбирать нечего, а `save_mode=last` открывал yazi не в каталоге, предложенном Firefox, что пользователь счёл непонятным. В `hyprland.lua` правило окна для класса `termfilechooser`: плавающее по центру, 1100×700; прозрачность и размытие те же, что у wezterm (класс добавлен в правило `blur-terminal-focused`), по требованию пользователя. Чтобы приложения вообще спрашивали файл через портал, в `hl.env` добавлен `GTK_USE_PORTAL=1`: GTK-приложения и Firefox в режиме «auto» переходят на портал по этой переменной; Qt и Chromium в Wayland используют портал сами. yazi установлен через mise, его каталог есть в `PATH` пользовательского systemd, откуда стартует служба портала. Решение принято 2026-09-10 по просьбе пользователя в ходе проверки 6.5. Альтернатива «отдельное изменение после hyprland-config» отклонена пользователем.

**D16. Настройки VA-API в основном профиле Firefox через `user.js`.**
Требование «Окружение клиентов для NVIDIA» спецификации hyprland-session оговаривает, что Firefox на NVIDIA включает VA-API только с набором настроек профиля; они были в пробном профиле `~/.cache/ff-nvcheck`, удалённом после проверки NVIDIA, а в основном профиле (`~/.config/mozilla/firefox/3e5c3xuj.default-release/`) их не оказалось, и при сводке 7.3 декодер по `nvidia-smi dmon` простаивал. По решению пользователя 2026-09-10 в основной профиль добавлен `user.js` с `media.hardware-video-decoding.force-enabled`, `media.ffmpeg.vaapi.enabled`, `media.rdd-ffmpeg.enabled`, `gfx.x11-egl.force-enabled`, `widget.dmabuf.force-enabled` и `media.av1.enabled=false`. Файл под chezmoi не берётся (профиль Firefox с личными данными), поэтому его содержимое зафиксировано здесь. Цена: настройки принудительно применяются при каждом старте Firefox, AV1 отключён (YouTube переходит на VP9 или H.264). Откат — удалить файл.

## Risks / Trade-offs

- [lightdm запускает Wayland-сессию иначе, чем X11: без login-оболочки, без `PATH` из `~/.profile`] → первая задача проверяет вход из greeter и `PATH` в терминале сессии; `hl.env("PATH", …)` в конфиге страхует запуск `wezterm-gui` и скриптов из `~/.local/bin`.
- [Собственный `hyprland-session.target` конфликтует с будущей встроенной интеграцией Hyprland] → при обновлении Hyprland до версии с интеграцией цель удаляется по инструкции вики (`systemctl --user revert`), обработчики в конфиге убираются; в конфиге стоит комментарий с этим условием.
- [Падение Hyprland при выходе (aquamarine) не даст сработать `hyprland.shutdown`] → `graphical-session.target` остаётся активным до следующего входа; при входе в Openbox юниты voxtype и hyprpolkitagent могут оказаться запущенными без композитора. Смягчение: в `autostart.sh` Openbox добавляется `systemctl --user stop graphical-session.target` в начале; проверка в задачах.
- [Правило «все окна плавающие» ломает диалоги, которые ожидают мозаику, или окна с фиксированной геометрией] → правило исключает `pin` и fullscreen, размер окон задают сами приложения; наблюдение первые дни, корректировки правилами по классу.
- [nm-applet без панели не показывает значок, а его секретный агент не нужен для проводной сети] → запускается ради будущей панели; если мешает, убирается одной строкой.
- [Xwayland-приложения (GIMP, Handy.AppImage) с масштабом 1 на 4K мелкие] → масштаб 1 выбран осознанно, как в X11; `xwayland.force_zero_scaling` не требуется.
- [`conceal_vrr_caps=1` лишает сессию VRR, а файл в `/etc/modprobe.d/` живёт вне chezmoi и потеряется при переустановке] → потеря VRR принята (D14): игры с переменной частотой пока не в приоритете, при необходимости параметр убирается с пересборкой initramfs; содержимое файла и проверка `modetest -M nvidia-drm -c` записаны в спецификации и tasks.md.
- [`GTK_USE_PORTAL=1` переводит на портал все GTK-диалоги сессии, а termfilechooser зависит от AUR и от yazi из mise] → диалоги печати и выбора приложения обслуживает gtk-портал, как и раньше; при поломке termfilechooser достаточно убрать строку `FileChooser=termfilechooser` из `hyprland-portals.conf` и перезапустить `xdg-desktop-portal`, вернётся диалог GTK.
- [`hyprctl reload` не перезапускает автозапуск] → так и задумано (D4); для перезапуска демонов есть `systemctl --user restart` и ручной запуск.

## Migration Plan

1. Установить пакеты: hyprpaper, hypridle, hyprlock, cliphist, wl-clipboard, grim, slurp.
2. Создать `dot_config/hypr/` (конфиг, конфиги hyprpaper, hypridle, hyprlock, скрипты) и `dot_config/systemd/user/hyprland-session.target`. Перед `chezmoi apply` пробный `~/.config/hypr/hyprland.lua` переименовывается в `hyprland.lua.trial`, чтобы chezmoi не сообщал о конфликте; файл удаляется после прохождения чек-листа.
3. `systemctl --user enable voxtype.service hyprpolkitagent.service` (стартуют только при активной цели).
4. Выйти из Openbox, в greeter выбрать «Hyprland», пройти чек-лист из tasks.md; при проблемах выбрать Openbox и продолжить оттуда.
5. Откат: выбор сессии Openbox в greeter; `chezmoi forget` для `dot_config/hypr/` и `dot_config/systemd/user/` не требуется, файлы никому не мешают; `systemctl --user disable` юнитов при необходимости.

## Open Questions

- Нужен ли `xwayland.force_zero_scaling` и `GDK_SCALE` для приложений Xwayland: решится по ощущениям после первых дней, спецификаций не меняет.
- Стоит ли включить `misc.focus_on_activate` для окон, которые просят фокус (например, браузер по ссылке из терминала): наблюдение в работе, спецификаций не меняет.
