## Why

herdr стоит пакетом AUR `herdr-bin`, который обновляет системный юнит
`herdr-update.service`. Выпущен форк `duty-herdr` (значки состояния
агентов, цвета заголовков spaces, токен `focused_tab`, надёжный
`agent prompt`); он ставится в `~/.local/bin/herdr` и обновляется
командой `herdr update` из GitHub Releases `quiet-lab/duty-herdr`. Пакет
AUR и юнит обновления теряют смысл: условие пересмотра решения
`herdr-prestart` (D1) выполнено.

## What Changes

- Предстартовый сценарий `herdr-prestart` использует
  `~/.local/bin/herdr` и выполняет новый шаг `herdr update` перед
  установкой интеграции; сеть или Releases недоступны — шаг печатает
  причину, старт не задерживается.
- Системный юнит `herdr-update.service` и каталог `system/herdr-update/`
  удаляются; пакет `herdr-bin` удаляется из системы (root, по слову
  пользователя).
- `~/.config/herdr/config.toml`: значки состояния `[ui.status_icons]`,
  цвета заголовков spaces `[ui.sidebar.spaces]`, строка `focused_tab`
  в панели агентов.
- Документы об источниках программ и состоянии станции описывают форк.
- **BREAKING**: требования «Обновление herdr при загрузке» и «Вход
  после обновления herdr» удаляются; экран входа ждёт только туннели.

## Capabilities

### New Capabilities

### Modified Capabilities

- `hyprland-autostart`: «Вход после туннелей», «Предстартовая подготовка
  herdr»; удалены «Обновление herdr при загрузке» и «Вход после
  обновления herdr».

## Impact

- `dot_local/bin/handmade-scripts/executable_herdr-prestart`,
  `dot_config/systemd/user/herdr-prestart.service`,
  `dot_config/herdr/config.toml`.
- `system/herdr-update/` (удаляется), `docs/host-state.md`,
  `docs/package-sources.md`, `docs/package-sources-plan.md`,
  `docs/open-questions/amn0-tcp-mss.md`, `todo.md`.
