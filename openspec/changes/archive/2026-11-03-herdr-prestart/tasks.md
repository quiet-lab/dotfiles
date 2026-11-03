## 1. Система

- [x] 1.1 `system/herdr-update/`: сценарий `herdr-update`, юнит `herdr-update.service`, `install.sh`, README (D1, D2).
- [x] 1.2 Запросы к AUR через `curl --interface amn0`; обрыв TLS при пометке в туннель — открытый вопрос `docs/open-questions/amn0-tcp-mss.md` (D3).
- [x] 1.3 `system/herdr-update/install.sh files`: юнит установлен и включён, не запущен.

## 2. Сессия

- [x] 2.1 Сценарий `herdr-prestart` и юнит `herdr-prestart.service`; `workspaced.service` — `After=`, `Wants=` (D4, D5).
- [x] 2.2 `dot_config/herdr/config.toml`: `resume_agents_on_restore = false`; `[apps.herdr]` — `cwd` монорепозитория.
- [x] 2.3 `chezmoi apply` файлов задачи, `systemctl --user daemon-reload`, `enable herdr-prestart.service` без запуска.

## 3. Проверки

- [x] 3.1 `systemd-analyze verify` системного юнита, `systemd-analyze --user verify` пользовательских, `list-dependencies hyprland-session.target`, `is-enabled`.
- [x] 3.2 `herdr-prestart --dry-run` при запущенном сервере.
- [x] 3.3 Пробная сборка `herdr-bin` копией сценария от пользователя без установки (версия 0.9.4-1 вместо установленной, `pacman -U` заменён печатью): пакет собран за 18 с; проверка версии настоящим сценарием — «последняя версия».
- [x] 3.4 Первая настоящая отработка обоих юнитов — при следующей загрузке; проверка перенесена в `todo.md`, раздел «Открытые вопросы к пользователю».

## 4. Спецификации и документация

- [x] 4.1 Дельта hyprland-autostart; `openspec validate herdr-prestart --strict`.
- [x] 4.2 `docs/package-sources-plan.md`, `docs/host-state.md` при необходимости.
