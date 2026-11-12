## Why

Предстартовая подготовка herdr выполняет `claude update` (срок 90 с) и
`herdr update` (срок 10 с) до демона workspaced. При туннеле `amn0` без
рукопожатия имена не разрешаются, оба обновления выходят по сроку, и
`workspaced.service` стартует на 118-й секунде загрузки вместо 17-й
(`journalctl --user -b -u herdr-prestart`, `systemd-analyze --user blame`).
herdr собирается самим пользователем со своими патчами и обновляется
при пересборках; Claude Code пользователь обновляет вручную. Автообновление
обоих при старте сессии не нужно.

## What Changes

- Из сценария `herdr-prestart` удаляются `claude update` и `herdr update`;
  остаются быстрые шаги без сети: `herdr integration install claude` и
  чистый старт herdr.
- Обновлений при старте сессии нет ни в каком юните.
- Требование «Предстартовая подготовка herdr» заменяется двумя:
  «herdr из форка duty-herdr» и «Быстрая предстартовая подготовка herdr».

## Capabilities

### New Capabilities

### Modified Capabilities

- `hyprland-autostart`: требование «Предстартовая подготовка herdr».

## Impact

- `dot_config/systemd/user/herdr-prestart.service`,
  `dot_config/systemd/user/workspaced.service` (комментарий),
  `dot_local/bin/handmade-scripts/executable_herdr-prestart`.
- `docs/host-state.md`, `docs/package-sources-plan.md`, `todo.md`.
