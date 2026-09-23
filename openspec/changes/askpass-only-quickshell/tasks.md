## 1. Общий модуль оформления

- [x] 1.1 Причина найдена: `qs -c askpass` падает на «module "qs" is not installed» в `panel/NotificationService.qml` (коммит `3f7e9e1`), окно подключало панель целиком ссылкой `panel` — 23.09.2026
- [x] 1.2 `dot_config/quickshell/common/`: `Theme.qml` и `Tile.qml` перенесены из панели (`git mv`), свой `qmldir`; зависимости — только `QtQuick` (решение D1) — 23.09.2026
- [x] 1.3 Панель: ссылка `symlink_common`, из `qmldir` убраны `Theme` и `Tile`, `import qs.common` в 23 файлах — 23.09.2026
- [x] 1.4 askpass: `symlink_panel` удалён из источника, ссылка `~/.config/quickshell/askpass/panel` и прежние `panel/Theme.qml`, `panel/Tile.qml` в `$HOME` удалены, `symlink_common` и `import qs.common` — 23.09.2026
- [x] 1.5 `chezmoi apply`, перезапуск `quickshell-panel.service`: «Configuration Loaded», ошибок QML в журнале нового процесса нет — 23.09.2026
- [x] 1.6 `timeout 5 qs -c askpass` с `ASKPASS_FIFO` и `ASKPASS_MESSAGE`: «Configuration Loaded», в `log.qslog` ошибок загрузки нет — 23.09.2026

## 2. Обёртка sudo-askpass

- [x] 2.1 Запасной путь pinentry-gtk удалён; при сбое, отмене и завершении окна без ответа — строка в stderr и код 1 (решение D2) — 23.09.2026
- [x] 2.2 Проверка отказа: `env -u WAYLAND_DISPLAY sudo-askpass` — «не задана переменная WAYLAND_DISPLAY», код 1 — 23.09.2026
- [x] 2.3 `system/modprobe.d/nvidia-vrr.sh`: сообщения об окне pinentry заменены на окно Quickshell askpass — 23.09.2026

## 3. Программа askpass по умолчанию

- [x] 3.1 `system/sudo/sudo.conf` (копия `/etc/sudo.conf` со строкой `Path askpass`) и `system/sudo/README.md`; файл установлен `install -m 0644` через `sudo -A` — пароль принят окном Quickshell (решение D3) — 23.09.2026
- [x] 3.2 `SUDO_ASKPASS` в `hyprland.lua` (`hl.env` и `import-environment`) и в `dot_profile`; `hyprctl reload config-only`, `systemctl --user set-environment` для текущей сессии; процесс, запущенный композитором, видит переменную (решение D4) — 23.09.2026
- [x] 3.3 `sudo -k`, `env -u SUDO_ASKPASS sudo -A -p 'Проверка стандартного askpass после настройки sudo.conf' true` — код 0; `sudo -n true` — код 0 — 23.09.2026
- [x] 3.4 Polkit: модуль `Quickshell.Services.Polkit` есть, в сессии работает `hyprpolkitagent`; план в `design.md` (D5), задача в `todo.md` — 23.09.2026

## 4. Правила и документация

- [x] 4.1 `AGENTS.md`, раздел «Команды с правами root»: без pinentry, `sudo.conf` и `SUDO_ASKPASS` — 23.09.2026
- [x] 4.2 `dot_claude/CLAUDE.md`: раздел о повышении привилегий; `chezmoi apply ~/.claude/CLAUDE.md` — 23.09.2026
- [x] 4.3 Запись `docs/decisions/0008-askpass-quickshell-only.md`, указатель `docs/decisions/README.md`, `todo.md` — 23.09.2026
- [x] 4.4 `openspec validate askpass-only-quickshell --strict` — 23.09.2026

## 5. Проверка пользователем

- [x] 5.1 Окно при запросе пароля выглядит как плитка панели (заливка, рамка, шрифт, пояснение над полем), значок показывает набранный пароль, Escape отменяет — `sudo` сообщает, что пароль не предоставлен — подтвердил пользователь 23.09.2026: окно выглядит хорошо, Escape даёт отказ sudo («пароль не предоставлен», код 1)
- [x] 5.2 Панель выглядит как до переноса оформления: плитки, всплывающие окна, уведомления, окно подсказки клавиш — подтвердил пользователь 23.09.2026

## 6. Архивация

- [ ] 6.1 После архивации `work-area-center`: `openspec archive askpass-only-quickshell -y`
