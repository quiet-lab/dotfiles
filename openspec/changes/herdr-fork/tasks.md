## 1. Сценарий и конфиг

- [x] 1.1 `herdr-prestart`: `herdr=$HOME/.local/bin/herdr`, шаг `herdr update` со сроком 10 с (D2, D3), шапка и комментарии.
- [x] 1.2 `herdr-prestart.service`: описание и комментарий о сроке.
- [x] 1.3 `dot_config/herdr/config.toml`: `[ui.status_icons]`, `[ui.sidebar.spaces]`, `focused_tab` (D5); `herdr config check` — `config: ok`.
- [x] 1.4 `system/herdr-update/` удалён.

## 2. Документы и спецификация

- [x] 2.1 `docs/host-state.md`, `docs/package-sources.md`, `docs/package-sources-plan.md`, `docs/open-questions/amn0-tcp-mss.md`, `todo.md`.
- [x] 2.2 Дельта `hyprland-autostart`; `openspec validate herdr-fork --strict`.

## 3. Применение

- [x] 3.1 `chezmoi diff` затрагивает только `herdr-prestart` и `~/.config/herdr/config.toml`.
- [ ] 3.2 `chezmoi apply` двух файлов.
- [ ] 3.3 Удалить `herdr-bin` и системный `herdr-update.service` (root): `systemctl disable herdr-update.service`, удалить `/etc/systemd/system/herdr-update.service` и установленный сценарий, `pacman -Rns herdr-bin`; `herdr` по PATH — форк.
- [ ] 3.4 Перезапуск herdr (`herdr server reload-config` либо новый сервер) и проверка значков и цветов на экране.
- [ ] 3.5 Архивировать изменение (`openspec archive herdr-fork -y`).
