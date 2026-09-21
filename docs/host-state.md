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
initramfs, без которой параметр не действует. С 2026-09-21 файла в `/etc`
нет: состояние подготовлено к проверке, нужен ли параметр ещё — открытый
вопрос [`open-questions/nvidia-conceal-vrr-caps.md`](open-questions/nvidia-conceal-vrr-caps.md).
История параметра описана в решении D14
`../openspec/changes/archive/2026-09-10-hyprland-config/design.md`.

**`/etc/greetd/config.toml`** — конфиг менеджера входа. Источник лежит
в репозитории (`system/greetd/config.toml`), но chezmoi каталог `system/`
не применяет: в `/etc` файл кладёт сценарий `system/greetd/migrate.sh`
с правами root. Он же создаёт `/var/cache/tuigreet` с владельцем `greeter`,
без чего tuigreet не запоминает имя пользователя.

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
переключатель «Привлекать внимание к окну» («Уведомления и звуки»;
в английском интерфейсе «Draw attention to the window», в поиске настроек
находится по словам flash, bounce, taskbar) выключен. Включённым он при каждом сообщении просит у композитора
активацию окна, и Hyprland с общей настройкой `misc.focus_on_activate`
поднимает окно, отдаёт ему фокус и уходит на его стол (изменение
`../openspec/changes/telegram-no-focus-steal/`). После переустановки
системы или сброса `tdata` переключатель надо выключить заново; признак
того, что он включён, — окно Telegram, которое при сообщении само
поднимается и забирает фокус.

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
  GTK и dunst; рядом лежат `Nerd-Patched` и `Unifont`.
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
(переписывается демоном при каждом изменении) и `sessions/test.toml`,
а также `keys.lua` — копия сгенерированных привязок, которую
`hyprland.lua` загружает, если конфиг демона сломан. Восстанавливать
не нужно: демон заводит каталог заново, `default.toml` наполняется в работе,
`keys.lua` записывается при первом удачном перечитывании конфига.

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
по Super+B, Super+V и Super+Y от ярлыков не зависит.

Ярлык `~/.local/share/applications/com.getpostman.Postman.desktop`, наоборот,
под chezmoi (`dot_local/share/applications/`, рядом с переопределением
flatpak `dot_local/share/flatpak/overrides/com.getpostman.Postman`),
и он намеренно перекрывает ярлык, экспортированный flatpak.

## Резервные копии удалённого

**`~/work/archive/`** — история удалённого 2026-09-16 кода eww:
`eww-daemon-2026-09-16.bundle` (вся история демона),
`eww-fix-systray-x11-click-coords-2026-09-16.bundle` и каталог
`eww-patches/` с патчами ветки поверх master eww. В репозитории dotfiles
этого нет: спецификации `eww-*` лежат только
в `../openspec/changes/archive/`.
