## ADDED Requirements

### Requirement: Программа запроса пароля в окружении сессии
Сессия MUST задавать переменную окружения `SUDO_ASKPASS=/home/mne/.local/bin/handmade-scripts/sudo-askpass` (окно Quickshell askpass, спецификация qs-askpass): в `dot_config/hypr/hyprland.lua` через `hl.env` и в `~/.profile`. Hyprland MUST передавать её в окружение пользовательского systemd тем же `systemctl --user import-environment`, что и остальные переменные `hl.env`, чтобы её видели юниты и приложения, запущенные демоном workspaced.

#### Scenario: Клиент и юнит видят переменную
- **WHEN** из сессии запущен терминал, а также выполнена `systemctl --user show-environment`
- **THEN** в окружении терминала и в выводе команды есть `SUDO_ASKPASS` с путём к обёртке
