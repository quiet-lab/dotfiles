## MODIFIED Requirements

### Requirement: Запуск сессии
Сессия Hyprland MUST запускаться менеджером входа greetd записью `hyprland.desktop` из пакета (`/usr/bin/start-hyprland`). Экран входа — tuigreet на виртуальной консоли 1 с командой `start-hyprland`, без выбора сессии; при загрузке greetd MUST запускать сессию пользователя без ввода пароля (раздел `[initial_session]`), а после выхода из сессии MUST показывать tuigreet с вводом пароля. Конфиг `/etc/greetd/config.toml` MUST совпадать с `system/greetd/config.toml` репозитория; chezmoi этот каталог не применяет. Выход из Hyprland MUST останавливать `graphical-session.target`, чтобы пользовательские юниты сессии не пережили её. LightDM, Xorg и uwsm MUST NOT использоваться для запуска; запись `hyprland-uwsm.desktop` остаётся в меню как неиспользуемая.

#### Scenario: Автовход при загрузке
- **WHEN** система загружена и служба `greetd.service` активна
- **THEN** Hyprland запускается с конфигом из `~/.config/hypr/hyprland.lua` без экрана входа, а в терминале сессии `echo $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP` даёт `wayland Hyprland`

#### Scenario: Выход в greeter
- **WHEN** пользователь завершает сессию Hyprland
- **THEN** tuigreet показывает запомненное имя пользователя и поле пароля, `graphical-session.target` пользователя остановлен

#### Scenario: Вход в Hyprland через greeter
- **WHEN** в tuigreet введён пароль пользователя
- **THEN** запускается Hyprland с конфигом из `~/.config/hypr/hyprland.lua` и автозапуском, `chezmoi status` не показывает расхождений

#### Scenario: Вход через tuigreet не удался
- **WHEN** после переключения служб tuigreet не запускает Hyprland
- **THEN** на другой виртуальной консоли вход по паролю и `systemctl enable --now lightdm` возвращают прежний экран входа, пока LightDM ещё не удалён
