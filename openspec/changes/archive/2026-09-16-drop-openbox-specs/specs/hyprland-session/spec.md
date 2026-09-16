## ADDED Requirements

### Requirement: Запуск сессии
Сессия Hyprland MUST запускаться из lightdm записью `hyprland.desktop` из пакета (`/usr/bin/start-hyprland`), выбранной в greeter. Выбранная сессия запоминается lightdm для следующего входа (`~/.dmrc`). Выход из Hyprland MUST останавливать `graphical-session.target`, чтобы пользовательские юниты сессии не пережили её. uwsm MUST NOT использоваться для запуска; запись `hyprland-uwsm.desktop` остаётся в меню как неиспользуемая.

#### Scenario: Вход в Hyprland через greeter
- **WHEN** в greeter lightdm выбрана сессия «Hyprland» и введён пароль
- **THEN** запускается Hyprland с конфигом из `~/.config/hypr/hyprland.lua`, `loginctl show-session` показывает `Type=wayland`, а `echo $XDG_SESSION_DESKTOP` в терминале сессии даёт `Hyprland`

#### Scenario: Выход в greeter
- **WHEN** пользователь завершает сессию Hyprland
- **THEN** lightdm показывает greeter, повторный вход запускает Hyprland с автозапуском, `chezmoi status` не показывает расхождений

## REMOVED Requirements

### Requirement: Запуск сессии из lightdm
**Reason**: Сессия Openbox удалена, сценарии возврата в неё невыполнимы.
**Migration**: Требование «Запуск сессии» описывает запуск из lightdm без второй сессии.
