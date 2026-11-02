## Why

На станции работают два туннеля: AmneziaWG `amn0` (системная служба
`awg-quick@amn0`, выбор маршрута по адресу назначения —
`docs/amnezia-split-tunnel.md`) и OpenVPN `axata` (соединение
NetworkManager). Их состояние в панели не видно: плитка сети показывает
только первое активное VPN-соединение NetworkManager, а `amn0`
NetworkManager не управляет. Чтобы узнать, поднят ли туннель, когда был
последний handshake и когда обновлялись списки стран, нужно открывать
терминал и вводить пароль.

`axata` поднимает сессия Hyprland сценарием `vpn-up`, который ждёт сеть
циклом `sleep 1` — опрос, запрещённый записью
`docs/decisions/0007-no-timers.md`. Демон workspaced открывает herdr
и браузеры раньше, чем туннель гарантированно поднят, а без входа
в сессию туннеля нет вовсе.

## What Changes

- В трее панели сверху два значка туннелей — `amn0` и `axata`: цвет
  глифа показывает состояние (поднят, поднимается, не поднят, ошибка),
  подсказка — краткое состояние, левый клик — окно состояния и настроек,
  правый — меню действий. Состояние обновляется только по событиям:
  `ip monitor` и журнал службы для `amn0`, поток `nmcli monitor` для
  `axata`.
- Поток `nmcli monitor` панели становится общим (синглтон `NmMonitor`):
  плитка сети и значок `axata` пользуются одним процессом.
- Правило `/etc/sudoers.d/amn-switch` дополняется командами с точными
  аргументами: чтение endpoint и времени handshake (`awg show amn0
  endpoints`, `awg show amn0 latest-handshakes`), числа элементов набора
  `zones` (`amn-zones-update --count`) и обновление списков стран
  (`amn-zones-update --force`).
- **BREAKING**: `axata` поднимается при загрузке системы системным
  юнитом `axata-vpn.service`, а не сессией; сценарий `vpn-up` и его вызов
  из `hyprland.lua` удаляются. Юнит `tunnels-before-login.service`
  задерживает экран входа greetd, пока поднимаются `amn0` и `axata`,
  не дольше 90 с от начала загрузки.
- Самопроверка `amn-switch` узнаёт внешний адрес прямого выхода у
  `ip.ru.net` вместо `2ip.ru`, который отвечает на curl кодом 503.

## Capabilities

### New Capabilities

### Modified Capabilities

- `qs-tray-lang`: значки туннелей в трее, их окно и меню; значки
  StatusNotifierItem стоят под ними.
- `hyprland-autostart`: требование «VPN при старте сессии» заменяется
  требованием «Туннели при загрузке системы».
- `qs-network`: общий поток событий NetworkManager; `axata` поднимает
  система, а не сессия.

## Impact

- Панель: `dot_config/quickshell/panel/` — `NmMonitor.qml`, `Tunnels.qml`,
  `TunnelPopup.qml`, `tiles/Tray.qml`, `tiles/Network.qml`,
  `scripts/tunnelstate`, `scripts/tunnelinfo`, `qmldir`.
- Сессия: `dot_config/hypr/hyprland.lua`, удалён
  `dot_local/bin/handmade-scripts/executable_vpn-up`.
- Система: `system/tunnels/` (юниты и `install.sh`),
  `system/sudo/sudoers.d/amn-switch`, `system/amnezia/amn-switch`.
- Документы: `docs/amnezia-split-tunnel.md`, `system/amnezia/README.md`,
  `system/tunnels/README.md`, `docs/host-state.md`, `AGENTS.md`.
