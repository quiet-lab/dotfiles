## 1. Подготовка (репозиторий, без sudo)

- [x] 1.1 `system/greetd/config.toml`: tuigreet с `--cmd start-hyprland --time --remember`, автовход `[initial_session]`, `vt = 1`
- [x] 1.2 `system/greetd/migrate.sh`: этапы `prepare` и `cleanup`, `bash -n`
- [x] 1.3 `.chezmoiignore`: каталог `system`; `chezmoi status` без расхождений

## 2. Переключение (интерактивный sudo, из текущей сессии)

- [x] 2.1 `sudo system/greetd/migrate.sh prepare`: установлены `greetd` и `greetd-tuigreet`, удалены `sxhkd` и `dmenu`, конфиг в `/etc/greetd/config.toml`, `systemctl is-enabled greetd` даёт `enabled`, `lightdm` — `disabled`
- [ ] 2.2 Перезагрузка. Сценарий «Автовход при загрузке»: Hyprland поднимается без экрана входа, `systemctl is-active greetd` даёт `active`
- [ ] 2.3 В терминале сессии: `echo $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP` даёт `wayland Hyprland`, `echo $PATH` содержит `~/.local/bin`, workspaced и панель Quickshell запущены
- [ ] 2.4 Выход из Hyprland. Сценарии «Выход в greeter» и «Вход в Hyprland через greeter»: tuigreet показывает имя пользователя, после пароля запускается Hyprland; `chezmoi status` без расхождений

## 3. Очистка (интерактивный sudo, из сессии greetd)

- [ ] 3.1 `sudo system/greetd/migrate.sh cleanup`: удалены `lightdm`, `lightdm-slick-greeter` и осиротевшие пакеты; `pacman -Q xorg-server` сообщает, что пакет не найден; `~/.dmrc`, `~/.xprofile`, `~/.xsession-errors` удалены
- [ ] 3.2 `ps -e | rg -i 'Xorg|lightdm'` пусто, `pacman -Qq | rg '^xorg-'` показывает только `xorg-xwayland` и зависимости Steam и gamescope

## 4. Документация

- [ ] 4.1 `dot_config/hypr/hyprland.lua`: комментарии о запуске (строки о lightdm) — greetd и tuigreet; `chezmoi apply`
- [ ] 4.2 CLAUDE.md и AGENTS.md: вход через greetd, каталог `system/`
- [ ] 4.3 Дельта hyprland-session, `openspec validate greetd-login --strict`
