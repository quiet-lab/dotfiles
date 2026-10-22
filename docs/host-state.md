# Что не лежит под chezmoi

Часть окружения под chezmoi не попадает: файлы `/etc`, профили программ
с личными данными, сборки из исходников, состояние демона, ярлыки,
созданные другими программами. При переустановке системы всё это придётся
восстанавливать руками, поэтому здесь перечислено, что именно и откуда.

Каждый путь проверен 2026-09-21: несуществующего в перечне нет.

## Файлы вне `$HOME`

**`/etc/modprobe.d/nvidia-vrr.conf`** — `options nvidia_modeset
conceal_vrr_caps=1`: скрывает от драйвера возможности VRR монитора, иначе
при 120 и 98 Гц картинка темнее и шрифты хуже. Копия файла лежит
в репозитории (`system/modprobe.d/nvidia-vrr.conf`), но chezmoi каталог
`system/` не применяет: в `/etc` файл кладёт, а оттуда убирает сценарий
`system/modprobe.d/nvidia-vrr.sh` (`restore` и `remove`), он же пересобирает
initramfs, без которой параметр не действует. Файл в `/etc` на месте;
почему от VRR отказались и как проверить изъян заново —
в [`decisions/0006-nvidia-conceal-vrr-caps.md`](decisions/0006-nvidia-conceal-vrr-caps.md).

**`/etc/greetd/config.toml`** — конфиг менеджера входа. Источник лежит
в репозитории (`system/greetd/config.toml`), но chezmoi каталог `system/`
не применяет: в `/etc` файл кладёт сценарий `system/greetd/migrate.sh`
с правами root. Он же создаёт `/var/cache/tuigreet` с владельцем `greeter`,
без чего tuigreet не запоминает имя пользователя.

**`/etc/sudo.conf`** — строка `Path askpass
/home/mne/.local/bin/handmade-scripts/sudo-askpass`: `sudo -A` запускает
окно Quickshell askpass и без переменной `SUDO_ASKPASS`. Копия файла лежит
в репозитории (`system/sudo/sudo.conf`), установка вручную описана
в `system/sudo/README.md`. Файл принадлежит пакету sudo; при его обновлении
pacman кладёт рядом `/etc/sudo.conf.pacnew`, и строку надо перенести
(запись [`decisions/0008-askpass-quickshell-only.md`](decisions/0008-askpass-quickshell-only.md)).

**Служба `avahi-daemon`** (пакет `avahi`) выключена и остановлена
17.10.2026 по решению пользователя: `systemctl disable --now
avahi-daemon.socket avahi-daemon.service`. Пакет остаётся, его требуют
`libcups` (через неё `gtk3` и всё графическое), `pipewire-pulse`, `ostree`,
`tinysparql`, `vlc-plugin-avahi`, а также явно установленные `mpd`
и `nss-mdns`. Потребителей у демона нет: `cups` не установлен, имена
`.local` разрешает `systemd-resolved` со своим клиентом mDNS (модуль `mdns`
в `/etc/nsswitch.conf` не подключён), браузеры ищут Chromecast собственными
сокетами на порту 5353, `mpd` не запущен. Включить обратно: `systemctl
enable --now avahi-daemon.socket`. Запуск по D-Bus (`org.freedesktop.Avahi`)
после `disable` тоже не срабатывает: ссылка `dbus-org.freedesktop.Avahi.service`
удалена.

**Выключенное 17.10.2026 по решению пользователя** (после разбора служб
без потребителей; пакеты остаются, если не сказано иное):
- висячая ссылка `multi-user.target.wants/ly@tty2.service` удалённого
  дисплейного менеджера ly удалена;
- `ollama.service` (сервер в `/usr/local/bin`, юнит в `/etc/systemd/system`)
  остановлен и снят с автозапуска: за сутки журнала ни одного запроса
  к API, потребителей в конфигах нет; модели в каталоге ollama (около
  45 ГБ) не тронуты, при нужде `ollama serve` вручную;
- Wi-Fi выключен `nmcli radio wifi off` (NetworkManager помнит состояние):
  работа идёт по проводу, wlan0 ни разу не подключался, а каждое
  сканирование эфира порождало тысячи строк в журнале от AmneziaVPN;
- `upower.service` замаскирован (`systemctl mask --now`): батареи нет,
  демон поднимал по D-Bus, вероятно, Chromium ради Battery Status API;
  `power-profiles-daemon` оставлен (его поднимает Telegram через
  GPowerProfileMonitor из GLib; демон выставляет EPP под профиль
  `balanced`, без него значение не проверено);
- `AmneziaVPN.service` и `sshd-unix-local.socket` оставлены по решению
  пользователя.
- пакет `lvm2` удалён вместе с `thin-provisioning-tools` и `libaio`
  (`pacman -Rns lvm2`): томов LVM нет ни на одном диске, хука `lvm2`
  в initramcpio не было; юниты `lvm2-monitor`, `lvm2-lvmpolld.socket`
  ушли с пакетом, `dm-event.socket` пакета device-mapper остался
  статическим и без lvm2 не запускается. Упавшие юниты
  `systemd-coredump@` сброшены `systemctl reset-failed`.

**`/etc/systemd/coredump.conf.d/50-size-limit.conf`** — предел размера
дампа памяти 4 ГиБ для всех программ (`ProcessSizeMax`, `ExternalSizeMax`);
причина — десять дампов безоконных Chromium по 32 ГиБ при ночном прогоне
тестов 17.10.2026 и вызванный ими OOM. Копия и установка —
`system/systemd/`. В самом проекте прогонов (`monorepo-ocp`) предел core
для процессов прогона задан нулевым отдельно.

**Docker без root.** Системные `docker.service` и `docker.socket`
выключены (`systemctl disable --now`), пакет `docker` остаётся; демон —
пользовательская служба из пакета AUR `docker-rootless-extras` (собран
`makepkg`, зависимость `rootlesskit` из `extra`). Включены
`systemctl --user enable --now docker.socket docker.service`, контекст
`rootless` в `~/.docker/config.json` (`docker context use rootless`),
переменная `DOCKER_HOST` — в `dot_profile`. Настройка сети —
`~/.config/systemd/user/docker.service.d/override.conf` (под chezmoi; pasta, порты
через pesto, петля машины из контейнеров открыта); почему так и как
вернуть демон с root — документ `docs/dev-stand.md` монорепозитория
`monorepo-ocp`, раздел «Docker без root». Образы прежнего демона лежат
в `/var/lib/docker`, новый хранит свои в `~/.local/share/docker`.
Контейнер `distrobox` работает на podman и от смены не зависит.

## Профили и настройки программ

**`~/.config/mozilla/firefox/3e5c3xuj.default-release/user.js`** — настройки
VA-API для Firefox на NVIDIA: без них аппаратный декодер не включается.
Отдельно там же выключен AV1 (`media.av1.enabled=false`), чтобы YouTube
отдавал VP9 или H.264, которые карта декодирует сама.
Профиль Firefox под chezmoi не берётся (личные данные),
поэтому содержимое файла записано в решении D16
`../openspec/changes/archive/2026-09-10-hyprland-config/design.md`; подробности
в [`media-and-portals.md`](media-and-portals.md). Обратите внимание:
профиль лежит в `~/.config/mozilla/firefox/`, а не в `~/.mozilla`.

**`~/.local/share/TelegramDesktop/tdata`** — настройки Telegram Desktop
в закрытом виде, под chezmoi не берутся. Одна из них важна для сессии:
переключатель «Подсветка окна» («Уведомления и звуки»;
в английском интерфейсе «Draw attention to the window», в поиске настроек
находится по словам flash, bounce, taskbar) выключен. Включённым он при каждом сообщении просит у композитора
активацию окна, и Hyprland с общей настройкой `misc.focus_on_activate`
поднимает окно, отдаёт ему фокус и уходит на его стол (изменение
`../openspec/changes/telegram-no-focus-steal/`). После переустановки
системы или сброса `tdata` переключатель надо выключить заново; признак
того, что он включён, — окно Telegram, которое при сообщении само
поднимается и забирает фокус.

**`~/.config/yandex-browser/Local State`** — настройки `browser://flags`
Яндекс.Браузера, под chezmoi не берутся (профиль). Значимая одна: флаг
`hardware-media-key-handling` должен стоять в «Default» — в «Disabled»
браузер не регистрируется как MPRIS-плеер, и пауза VoxType с привязками
`playerctl` его не видят (подробности в [`media-and-portals.md`](media-and-portals.md),
раздел «Браузеры на Chromium»). Признак сбоя — `playerctl -l` не показывает
`chromium.instance…` при играющем видео.

**`Preferences` профилей браузеров** — настройка «При запуске» у Chromium
(`~/.config/chromium/Default`), Chrome в обоих каталогах данных
(`~/.config/google-chrome/Default`, `~/.config/google-chrome-ai/Default`)
и Яндекс.Браузера (`~/.config/yandex-browser/Default`); профили под chezmoi
не берутся. От неё зависит, вернутся ли после перезагрузки вторые окна
браузеров: демон запускает браузер один раз для первого экземпляра,
а остальные окна открывает сам браузер, если в профиле выбрано
«Продолжить с того же места» (`session.restore_on_startup = 1`); демон
раскладывает их по записям снимка сессии (изменение
`../openspec/changes/session-instances/`, решение D3). Решением пользователя
23.09.2026 настройка включена во всех четырёх профилях: ключ
`session.restore_on_startup = 1` вписан в `Preferences` при закрытом
браузере (запущенный браузер при выходе переписывает файл). Проверено после
перезапуска каждого браузера: значение 1 сохранилось, браузер восстановил
прежние вкладки (запись типа 1 в `sessions.event_log` профиля: Chromium —
1 вкладка, Chrome — 116, Chrome AI.dev2026 — 1, Яндекс.Браузер — 14).
Ключ отслеживаемый: под `protection.macs.session` лежат HMAC-SHA256 значения
и его зашифрованный хеш, и при ручной правке их нужно пересчитать, иначе
браузер может счесть настройку подменённой и сбросить её. Ключ HMAC
у Chromium пустой, у Chrome — ресурс `IDR_PREF_HASH_SEED_BIN` из
`resources.pak`, сообщение — путь ключа и значение в JSON (`session.restore_on_startup1`);
зашифрованный хеш — SHA-256 от ключа HMAC и того же сообщения,
зашифрованный по схеме `v10` (AES-128-CBC, ключ PBKDF2 от `peanuts`).
Ключ HMAC Яндекс.Браузера в `resources.pak` не найден, поэтому в его профиле
вписано только значение; браузер его принял и сам пересчитал отпечаток.
Признак того, что настройка включена, — `session.restore_on_startup`
со значением 1 в `Preferences` профиля; выключить её можно в настройках
браузера («При запуске»), файл при этом править не нужно.

**`~/.config/git-credentials` и `~/.config/gh/hosts.yml`** — пароль к git
и токен `gh` в открытом виде. Под chezmoi не берутся намеренно.
Восстановление — новый вход: `gh auth login --with-token`, пароль git
запрашивается при первой операции с удалённым репозиторием.

## Темы, шрифты, обои и курсор

Наследие набора `cachyos-openbox-settings`: пакет не установлен, но копия
лежит в кэше pacman (`/var/cache/pacman/pkg/cachyos-openbox-settings-1.0.4-1-any.pkg.tar.zst`),
и файлы можно достать оттуда. Ни один из этих каталогов chezmoi
не отслеживает.

- **`~/.themes/Fleon`** — тема GTK, задана в `dot_gtkrc-2.0`
  и `dot_config/gtk-3.0/settings.ini` (`gtk-theme-name=Fleon`).
- **`~/.fonts/`** — `Comfortaa` и `IcoMoon-Custom` нужны rofi, `Cantarell` —
  программам GTK; рядом лежат `Nerd-Patched` и `Unifont`.
- **`~/.wallpapers/mechanical/`** — обои сессии; `hyprpaper.conf` указывает
  на `okita-souji_FHD.jpg`, остальные файлы каталога запасные.
- **`~/.icons/default/index.theme`** — тема курсора, наследует
  `capitaine-cursors` (файл написан LXAppearance, самой программы
  в системе уже нет).

Темы значков и курсоров лежат в пакетах `breeze-icons`
и `capitaine-cursors`. По пакетным связям от них не зависит ничего, ссылки
на них есть только в конфигах, поэтому оба помечены как явно установленные —
иначе очистка сирот их унесёт, как однажды унесла `breeze-icons`
(см. [`agent-session-tips.md`](agent-session-tips.md)).

## Сборки из исходников и ссылки

**`~/builds/wezterm`** — wezterm собран из исходников с поддержкой Wayland
(в репозиториях пакета нет; версия 20260805-104032-4b1c3c15). Ссылки
`~/.local/bin/wezterm`, `wezterm-gui`, `wezterm-mux-server` указывают
в `target/release/`. Восстановление — клон wezterm и `cargo build
--release`.

**`~/.local/bin/workspaced`** — ссылка на
`~/work/pets/workspaced/target/release/workspaced`. Сам проект — отдельный
публичный репозиторий `git@github.com:quiet-lab/workspaced.git`, сборка
`cargo build --release`. В dotfiles попадают только конфиг
(`dot_config/workspaced/config.toml`) и юнит
(`dot_config/systemd/user/workspaced.service`).

## Состояние демона workspaced

**`~/.local/state/workspaced/`** — сессии `sessions/default.toml`
(пишется только командой сохранения, Ctrl+Super+S дважды) и `sessions/test.toml`,
а также `keys.lua` — копия сгенерированных привязок, которую
`hyprland.lua` загружает, если конфиг демона сломан. Восстанавливать
не нужно: демон заводит каталог заново, `default.toml` появляется при первом сохранении,
`keys.lua` записывается при первом удачном перечитывании конфига.

## Контейнер distrobox `fedora-box`

Сам контейнер под chezmoi не попадает: его настройки хранит база podman
`~/.local/share/containers/storage/db.sql`. Из dotfiles к нему относятся
только юнит прогрева `dot_config/systemd/user/distrobox@.service` и ярлыки
(см. ниже). Восстановление после переустановки — `distrobox create` с ключом
`--nvidia` на образе `registry.fedoraproject.org/fedora:latest` и установка
браузеров внутри.

**Политика перезапуска — `always`** (`podman update --restart=always
fedora-box`, поле `restart_policy` в базе podman; проверяется
`podman inspect fedora-box --format '{{json .HostConfig.RestartPolicy}}'`).
Без неё смерть контейнера оставалась незамеченной до следующего нажатия
клавиши браузера: `distrobox-enter` обнаруживал остановленный контейнер,
запускал его сам и ждал в `podman logs -f` строку `container_setup_done`.
Строка теряется в потоке трассировки entrypoint (см. ниже), и ожидание
затягивалось на часы. С политикой `always` podman поднимает контейнер сам
сразу после смерти — по событию выхода, без опроса, — и `distrobox-enter`
застаёт его работающим, минуя чтение журнала. Явную остановку
(`podman stop` из `ExecStop` юнита при выходе из сессии) политика
не отменяет. Контейнер делит с хостом пространство PID, поэтому его
процесс завершит любая команда на хосте, рассылающая сигналы чужим
процессам; подробности — в [`media-and-portals.md`](media-and-portals.md).

**Трассировку entrypoint выключить нельзя.** `distrobox-create` (версия
1.8.2.5, строка 994 `/usr/bin/distrobox-create`) безусловно, независимо
от своего ключа `--verbose`, дописывает `--verbose` в аргументы entrypoint,
а `distrobox-init` по этому флагу включает `set -o xtrace`. Флаг лежит
в `Config.Cmd` контейнера, то есть в базе podman; `podman update` меняет
только ограничения ресурсов, проверки работоспособности, переменные
окружения и политику перезапуска, а правка `config.json` в хранилище
бесполезна — podman собирает его из базы при каждом запуске. Переменной
окружения или файла настроек, отключающих трассировку, `distrobox-init`
не читает. Пересоздание контейнера тоже не помогло бы: `--verbose` добавится
снова. За 7 секунд запуска entrypoint выдаёт больше 15 000 строк,
и journald их ограничивает («Suppressed … messages from user@1000.service»),
теряя в том числе `container_setup_done`.

**Драйвер журнала — `journald`** (`HostConfig.LogConfig.Type`). Сменить его
у существующего контейнера нечем: у `podman update` ключа `--log-driver`
нет, а значение хранится в базе. `k8s-file` ограничения скорости не знает,
поэтому при следующем пересоздании контейнера драйвер стоит задать
явно (`--log-driver k8s-file` в `container_manager_additional_flags`
или `log_driver` в `~/.config/containers/containers.conf`).

## Ярлыки приложений

**`~/.local/share/applications/fedora-box-*.desktop`** — записи,
экспортированные из контейнера distrobox `fedora-box`
(`fedora-box-google-chrome.desktop`,
`fedora-box-yandex-browser.desktop` и другие). В строках `Exec` стоят
ключи `--ozone-platform=wayland` и
`--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks`,
добавленные руками. Повторный `distrobox-export` записи перезапишет,
и ключи придётся вернуть. Те же ключи продублированы в аргументах
приложений демона (`dot_config/workspaced/config.toml`), поэтому запуск
браузеров клавишами демона (Super+B, Super+V, Super+Y в `surf`
и Shift+Super+B, Shift+Super+V, Shift+Super+Y — собственные клавиши
браузеров) от ярлыков не зависит.

Ярлык `~/.local/share/applications/com.getpostman.Postman.desktop`, наоборот,
под chezmoi (`dot_local/share/applications/`, рядом с переопределением
flatpak `dot_local/share/flatpak/overrides/com.getpostman.Postman`),
и он намеренно перекрывает ярлык, экспортированный flatpak.

**`~/.local/share/applications/fedora-box-google-chrome-ai.desktop`** —
ярлык отдельного экземпляра Chrome с профилем `AI.dev2026`, заведённого
изменением `app-families`. В отличие от соседних файлов этого каталога он
не экспортирован `distrobox-export`, а создан вручную по их образцу: у
Chrome нет средства перенести один профиль в собственный каталог данных
(диспетчер профилей Chrome умеет только удалить профиль или добавить
новый пустой), поэтому профиль скопирован файлами, а для него заведён
свой каталог данных и свой ярлык. В строке `Exec` — абсолютный путь
к каталогу данных `~/.config/google-chrome-ai` (`--user-data-dir`,
профиль `Default`), ключ `--class=google-chrome-ai` и `StartupWMClass=
google-chrome-ai`, те же ключи Wayland и VA-API, что и у соседних ярлыков.
Экземпляр работает отдельным процессом, и все его окна несут класс
`google-chrome-ai`, поэтому окна профилей `Default` и `AI.dev2026`
различаются по классу. Демон workspaced запускает тот же экземпляр теми же
ключами из `dot_config/workspaced/config.toml`, так что запуск по Super+V
и Shift+Super+V от ярлыка не зависит.

**Каталоги данных Chrome** — у каждого профиля Chrome собственный
каталог данных и собственный экземпляр браузера, чтобы демон различал окна
профилей по классу (приложения `chrome`, `chrome-ai` и `chrome-ai2`
в `dot_config/workspaced/config.toml`); под chezmoi каталоги не берутся.
`~/.config/google-chrome` — профиль `Default` («Alexandr»), класс окон
`google-chrome`. Профиль AI2 (`Profile 4`) жил здесь же до 17.10.2026;
после переноса его каталог и запись в `profile.info_cache` удалены
по решению пользователя, `profile.last_used` и
`profile.last_active_profiles` указывают на `Default`. Запись из
`Local State` убиралась при работающем Chrome: если «AI2» снова появится
в меню профилей этого экземпляра, значит Chrome перезаписал файл своей
копией, и запись надо удалить ещё раз при закрытом браузере.
`~/.config/google-chrome-ai` — профиль AI.dev2026, класс `google-chrome-ai`.
`~/.config/google-chrome-ai2` — профиль AI2, перенесённый 17.10.2026 копией
каталога `Profile 4` в `Default` нового каталога; `Local State` сделан
из прежнего с единственной записью `Default` в `profile.info_cache`, класс
окон `google-chrome-ai2`. При первом запуске в новом каталоге Chrome показал
окна условий использования и приветствия, потому что в каталоге не было
отметки `First Run`. Настройка «При запуске» в профиле AI2 не задана, и
прежние вкладки после переноса не восстановились. Ярлыка в
`~/.local/share/applications` для AI2 нет: запускает его только демон.

## Резервные копии удалённого

**`~/work/archive/`** — история удалённого 2026-09-16 кода eww:
`eww-daemon-2026-09-16.bundle` (вся история демона),
`eww-fix-systray-x11-click-coords-2026-09-16.bundle` и каталог
`eww-patches/` с патчами ветки поверх master eww. В репозитории dotfiles
этого нет: спецификации `eww-*` лежат только
в `../openspec/changes/archive/`.
