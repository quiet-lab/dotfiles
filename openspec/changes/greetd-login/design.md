# Design: Вход через greetd и tuigreet вместо LightDM

## Context

Сейчас вход выполняет lightdm 1.33 со slick-greeter на tty7: `/etc/lightdm/lightdm.conf` указывает `user-session=openbox`, а сессия Hyprland выбирается в greeter и запоминается в `~/.dmrc`. Пользователь состоит в группе `nopasswdlogin`, поэтому пароль при входе не спрашивается. lightdm запускает Wayland-сессию без обёртки `Xsession`, окружение (`PATH`, переменные NVIDIA и Qt) задаёт `hyprland.lua` через `hl.env`.

greetd 0.10 запускает команду сессии через `/bin/sh -c` без login-оболочки, но по умолчанию (`source_profile = true`) выполняет `/etc/profile` и `~/.profile`. В окружение сессии он добавляет `XDG_SEAT`, `XDG_VTNR`, `XDG_SESSION_CLASS=user` и переменные PAM; `XDG_SESSION_TYPE` он не задаёт, поэтому logind показывает сессию как `Type=tty`. Hyprland сам выставляет клиентам `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=Hyprland` и `XDG_BACKEND`; `XDG_SESSION_DESKTOP`, которую задавал lightdm, никто не выставляет.

tuigreet 0.11 умеет запускать одну команду (`--cmd`) или предлагать выбор из `wayland-sessions`; запоминание пользователя (`--remember`) требует каталог `/var/cache/tuigreet`, принадлежащий пользователю `greeter`.

## Goals / Non-Goals

**Goals:**
- Вход без Xorg: экран входа и сессия работают только на Wayland и консоли.
- Поведение входа как прежде: при загрузке в сессию без пароля, после выхода — экран входа.
- Удаление LightDM и всех пакетов, которые держались только им.

**Non-Goals:**
- Графический экран входа (ReGreet, SDDM).
- Переход на uwsm или `hyprland-uwsm.desktop`.
- Управление файлами `/etc` через chezmoi.

## Decisions

**D1. tuigreet с одной командой `start-hyprland`, без выбора сессии.** Единственная сессия в системе — Hyprland, запись `hyprland-uwsm.desktop` по спецификации не используется. Список сессий (`--sessions`) добавил бы лишний шаг при входе и возможность выбрать uwsm по ошибке.

**D2. Автовход через `[initial_session]`.** Это ближайший эквивалент входа без пароля через `nopasswdlogin`: greetd при загрузке сразу запускает `start-hyprland` от имени пользователя, а после выхода из сессии показывает tuigreet с паролем. Группа `nopasswdlogin` с PAM greetd не связана и остаётся без действия; раздел легко удалить, если пароль нужен и при загрузке.

**D3. Конфиг и сценарий переезда живут в каталоге `system/` репозитория.** Файлы `/etc` в `$HOME` не попадают, поэтому chezmoi их не применяет; каталог исключён в `.chezmoiignore`, как `openspec`. Копирование в `/etc/greetd` делает сценарий `system/greetd/migrate.sh`, его запускает пользователь с интерактивным вводом пароля sudo.

**D4. Два этапа с перезагрузкой между ними.** Этап `prepare` ставит пакеты, кладёт конфиг, выключает `lightdm.service` и включает `greetd.service`, но работающий LightDM не останавливает и не удаляет: удаление менеджера входа из-под живой сессии может сломать выход из неё. Этап `cleanup` выполняется уже из сессии, поднятой greetd, и удаляет LightDM, slick-greeter и осиротевшие пакеты (`xorg-server`, `xorg-xrdb`, `xorg-xmodmap` и их зависимости), а также файлы пользователя от LightDM.

**D5. `source_profile` остаётся включённым.** `~/.profile` задаёт `PATH`, `QT_QPA_PLATFORMTHEME` и окружение cargo; всё нужное сессии `hyprland.lua` задаёт сам, так что чтение профиля — только страховка и не создаёт расхождений.

**D6. Сценарий спецификации проверяет `XDG_SESSION_TYPE` и `XDG_CURRENT_DESKTOP`, а не `loginctl` и `XDG_SESSION_DESKTOP`.** Эти переменные выставляет Hyprland, и именно на них смотрят клиенты (портал, Qt, Electron). `Type=tty` в logind на работу сессии не влияет.

## Risks / Trade-offs

- [Вход через tuigreet не удался, а lightdm уже выключен] → на любой консоли (Ctrl+Alt+F2) вход по паролю и `systemctl enable --now lightdm` возвращают прежний экран входа; пакет lightdm на этапе `prepare` не удаляется.
- [Автовход при загрузке пускает в сессию без пароля] → так же вело себя прежнее решение с `nopasswdlogin`; раздел `[initial_session]` удаляется одной правкой.
- [Каталог `/var/cache/tuigreet` не принадлежит `greeter`] → tuigreet работает, но не запоминает имя пользователя; сценарий создаёт каталог с нужным владельцем.
- [`pacman -Qdtq` после удаления LightDM называет пакеты, установленные не им] → сценарий печатает список и запрашивает подтверждение pacman, лишнее можно отклонить.
- [Приложение зависит от `XDG_SESSION_DESKTOP`] → переменная нужна в основном оболочкам GNOME и KDE; при обнаружении такой зависимости её можно добавить в `hyprland.lua` через `hl.env`.
