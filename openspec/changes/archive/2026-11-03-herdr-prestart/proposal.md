## Why

herdr, Claude Code и хуки интеграции herdr с Claude Code обновляются
вручную: пакет AUR `herdr-bin` — через `yay`, Claude Code — командой
`claude update` (автообновление в `~/.claude.json` выключено), хуки —
`herdr integration install claude` после каждого обновления herdr. Версии
расходятся, а хук состояния агента от прежней версии herdr не совпадает
с протоколом новой.

При старте сессии демон workspaced открывает herdr, и herdr восстанавливает
прежние workspace из `~/.config/herdr/session.json` вместе с агентами
(`claude --resume`). Решение запустить Claude Code принимает пользователь;
восстановленные агенты расходуют лимит и открывают давно закрытые задачи.

## What Changes

- Системный юнит `herdr-update.service` (`system/herdr-update/`) при
  загрузке, до экрана входа, сравнивает версию `herdr-bin` в AUR
  с установленной и при новой собирает пакет `makepkg` от пользователя
  и ставит `pacman -U`. Без сети и при ошибке юнит пишет причину в журнал
  и не задерживает вход дольше срока задания.
- Запросы сценария к AUR привязаны к туннелю `amn0` (`curl --interface`):
  помеченное в туннель соединение с AUR обрывается на рукопожатии TLS.
- Пользовательский юнит `herdr-prestart.service` в `hyprland-session.target`
  до демона workspaced: `claude update`, `herdr integration install claude`,
  а при незапущенном сервере herdr — перенос `session.json` в копию рядом
  (не больше десяти копий). `--dry-run` сценария печатает шаги, ничего
  не меняя.
- `~/.config/herdr/config.toml`: `[session] resume_agents_on_restore = false`.
- `[apps.herdr]` демона workspaced открывает herdr в каталоге
  `~/work/telecom/axata/monorepo-ocp`: при чистом старте herdr создаёт
  одно пространство там.

## Capabilities

### New Capabilities

### Modified Capabilities

- `hyprland-autostart`: требования «Обновление herdr при загрузке»
  и «Предстартовая подготовка herdr».

## Impact

- `system/herdr-update/` (новый каталог), `docs/open-questions/amn0-tcp-mss.md`.
- `dot_config/systemd/user/herdr-prestart.service`,
  `dot_config/systemd/user/workspaced.service`,
  `dot_local/bin/handmade-scripts/executable_herdr-prestart`.
- `dot_config/herdr/config.toml`, `dot_config/workspaced/config.toml`.
- `docs/package-sources-plan.md`, `docs/README.md` при необходимости.
