# Proposal: Вход через greetd и tuigreet вместо LightDM

## Why

LightDM со slick-greeter — последний компонент системы, которому нужен Xorg: экран входа рисуется X-сервером, и ради него в системе живут `xorg-server`, `xorg-xrdb` и `xorg-xmodmap`. Сессия при этом давно Wayland, все окна нативные, а Openbox удалён. Пользователь хочет убрать X11 из системы целиком, оставив только Xwayland для Steam и Wine.

## What Changes

- Экран входа переезжает на greetd с текстовым greeter tuigreet: без X-сервера и без композитора, Hyprland запускается записью `hyprland.desktop` из пакета.
- Автовход при загрузке через раздел `[initial_session]` greetd заменяет прежний вход без пароля через группу `nopasswdlogin`; после выхода из сессии показывается tuigreet с вводом пароля.
- LightDM, slick-greeter и осиротевшие пакеты X11 удаляются после проверки нового входа; попутно удаляются неиспользуемые `sxhkd` и `dmenu`.
- В репозитории появляется каталог `system/` для файлов вне `$HOME` (конфиг greetd, сценарий переезда); chezmoi его не применяет.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities
- `hyprland-session`: требование «Запуск сессии» — вход через greetd вместо lightdm.

## Impact

- Система: пакеты `greetd`, `greetd-tuigreet`; файл `/etc/greetd/config.toml`; службы `lightdm.service` (выключается) и `greetd.service` (включается); удаление `lightdm`, `lightdm-slick-greeter`, `sxhkd`, `dmenu` и осиротевших зависимостей.
- Репозиторий: `system/greetd/config.toml`, `system/greetd/migrate.sh`, `.chezmoiignore`; комментарии в `dot_config/hypr/hyprland.lua`; CLAUDE.md и AGENTS.md; спецификация hyprland-session.
- Файлы пользователя, оставшиеся от LightDM: `~/.dmrc`, `~/.xprofile` (дублирует `QT_QPA_PLATFORMTHEME` из `hyprland.lua`), `~/.xsession-errors`.
