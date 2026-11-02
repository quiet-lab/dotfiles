## Why

Страну выхода туннеля `amn0` видно только в приложении AmneziaVPN, а
сменить её можно только там же, после чего конфиг `amn0` приходится
выгружать заново. Значок `amn0` (глобус) не отличается от сетевых
значков. Значки туннелей не показывают, что туннель поднят, но трафик
через него не проходит: сервер не отвечает на рукопожатия, OpenVPN
перезапускается по `--ping-restart`.

## What Changes

- Значок `amn0` — знак анархии (геометрия SVG Wikimedia Commons); таблица состояний и цветов значков,
  новый цвет `Theme.orange` для состояния «поднят, связи нет».
- Подсказка и окно сведений `amn0` показывают выбранную страну, окно —
  ещё и фактическую страну выхода по ipinfo.io через `amn0`.
- Пункт меню «Страна туннеля…»: выбор страны подписки, конфиг от шлюза
  Amnezia тем же запросом, что приложение, установка сценарием root
  `amn-apply-config` с проверкой и откатом.
- Состояние «поднят, связи нет» по журналам: amneziawg-go в подробном
  режиме (drop-in `LOG_LEVEL=verbose`) и `nm-openvpn`.
- Правило sudoers `amn-switch` дополнено `amn-apply-config` без
  аргументов.

## Capabilities

### New Capabilities

### Modified Capabilities

- `qs-tray-lang`: требования «Значки туннелей», «Состояние туннелей по
  событиям», «Окно сведений туннеля», «Действия туннелей»; новые
  «Страна туннеля amn0», «Смена страны amn0», «Связь amn0», «Связь axata».

## Impact

- `dot_config/quickshell/panel/` (`Tunnels.qml`, `TunnelPopup.qml`,
  `tiles/Tray.qml`, `scripts/tunnelstate`, `scripts/tunnelinfo`),
  `dot_config/quickshell/common/Theme.qml`.
- `dot_local/bin/handmade-scripts/amn-country` (новый).
- `system/amnezia/` (`amn-apply-config`, `amn-export-config`,
  `install.sh`, drop-in `awg-quick@amn0.service.d/`),
  `system/sudo/sudoers.d/amn-switch`.
