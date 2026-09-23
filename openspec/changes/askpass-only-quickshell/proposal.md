## Why

23.09.2026 обнаружено, что окно ввода пароля Quickshell не загружается:
`qs -c askpass` завершается с ошибкой «Type Tile unavailable ←
panel/Tile.qml: Type KeysHelp unavailable ← panel/KeysHelp.qml:
NotificationService unavailable ← panel/NotificationService.qml[17]:
module "qs" is not installed». Окно подключало панель целиком модулем
`qs.panel` через ссылку `panel -> ../panel`, а среди синглтонов панели
с вечера 22.09.2026 есть файлы, которые импортируют модуль `qs` корня
панели; в корне askpass такого модуля нет. Всё это время пароль
спрашивал запасной диалог pinentry-gtk, и поломка оставалась
незамеченной.

Решение пользователя 23.09.2026: «Старый скрипт нужно удалить. Глобально
добавить правило: использовать askpass на Quickshell. По возможности
сделать его стандартной утилитой для ввода паролей для повышения
привилегий.» Запись решения —
[`docs/decisions/0008-askpass-quickshell-only.md`](../../../docs/decisions/0008-askpass-quickshell-only.md).

## What Changes

- Оформление (`Theme.qml`, `Tile.qml`) выносится из панели в общий
  модуль `dot_config/quickshell/common/` (`qs.common`), который от кода
  панели не зависит. Панель и окно askpass подключают его символической
  ссылкой `common -> ../common`; ссылка `askpass/panel` удаляется.
- Запасной путь pinentry-gtk удаляется из обёртки `sudo-askpass`
  целиком: если окно не запустилось или завершилось без ответа, обёртка
  пишет причину в stderr и завершается с кодом 1.
- `/etc/sudo.conf` получает строку `Path askpass` с путём к обёртке
  (копия — `system/sudo/sudo.conf`), а сессия задаёт переменную
  `SUDO_ASKPASS` (`hyprland.lua`, `~/.profile`): `sudo -A` находит окно
  без переменной в командной строке.
- Правило для агентов: права root — только `sudo -A -p '<зачем>'`,
  пароль спрашивает окно Quickshell askpass; `AGENTS.md` и общий
  `~/.claude/CLAUDE.md`.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `qs-askpass`: оформление из модуля `qs.common`; запасной путь
  pinentry-gtk удалён, отказ окна видит вызвавшая программа; обёртка —
  программа askpass по умолчанию для sudo.
- `qs-shell`: требование «Модульная структура конфигурации» — общие
  цвета и плитка лежат в модуле `qs.common`, а не в каталоге панели.
- `hyprland-session`: переменная `SUDO_ASKPASS` в окружении сессии.

## Impact

- `dot_config/quickshell/common/` — новый каталог: `Theme.qml`,
  `Tile.qml` (перенесены из панели), `qmldir`.
- `dot_config/quickshell/panel/` — ссылка `symlink_common`, из `qmldir`
  убраны `Theme` и `Tile`, в 23 файлах добавлен `import qs.common`;
  вид панели не меняется.
- `dot_config/quickshell/askpass/` — `symlink_panel` заменён на
  `symlink_common`, импорт `qs.common`.
- `dot_local/bin/handmade-scripts/executable_sudo-askpass` — без pinentry.
- `system/sudo/` — копия `sudo.conf` и README об установке.
- `dot_config/hypr/hyprland.lua`, `dot_profile` — переменная
  `SUDO_ASKPASS`.
- `system/modprobe.d/nvidia-vrr.sh` — сообщения об окне pinentry
  заменены на окно Quickshell askpass.
- `AGENTS.md`, `dot_claude/CLAUDE.md`, `docs/decisions/0008`, `todo.md`.
