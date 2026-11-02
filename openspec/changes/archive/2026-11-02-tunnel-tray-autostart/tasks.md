## 1. Панель Quickshell

- [x] 1.1 Синглтон `NmMonitor.qml`: общий поток `nmcli monitor` с перезапуском по выходу; `tiles/Network.qml` подписан на него (D3).
- [x] 1.2 Синглтон `Tunnels.qml`: состояние `amn0` по `ip monitor link address` и `journalctl -f -u awg-quick@amn0.service`, `axata` по `NmMonitor`; действия с ошибкой в состоянии (D2, D4).
- [x] 1.3 Сценарии `scripts/tunnelstate` и `scripts/tunnelinfo` (D2, D4).
- [x] 1.4 `TunnelPopup.qml` и значки в `tiles/Tray.qml`: глифы и цвета, подсказка, окно по левому клику, меню по правому, цель IPC `tunnels` (D1, D4).

## 2. Система

- [x] 2.1 `system/sudo/sudoers.d/amn-switch`: `awg show amn0 endpoints|latest-handshakes`, `amn-zones-update --count|--force`; установлено `system/amnezia/install.sh files` (D4).
- [x] 2.2 `system/tunnels/axata-vpn.service`, `tunnels-before-login.service`, `install.sh`; установлены и включены `system/tunnels/install.sh files` (D5, D6).
- [x] 2.3 Удалены `vpn-up` и его вызов из `hyprland.lua`, упоминания в `AGENTS.md`.
- [x] 2.4 `amn-switch`: внешний адрес прямого выхода — `ip.ru.net` (D7); установлен.

## 3. Проверка вживую

- [x] 3.1 Агент: перезапуск `quickshell-panel.service`, в журнале панели нет ошибок QML; `qs -c panel ipc call tunnels state` — оба туннеля `up`; снимок экрана — два зелёных значка над значками StatusNotifierItem; один процесс `nmcli monitor`.
- [x] 3.2 Агент: окно сведений `amn0` и `axata` по IPC (`info`, `shown`): endpoint, handshake, число элементов `zones` (27151), сервер `axata`; пароль не спрашивался.
- [x] 3.3 Агент: действие «Обновить списки стран» по IPC (`run`) — `zones.nft` обновлён, ошибки нет, пароль не спрашивался.
- [x] 3.4 Агент: `systemctl start axata-vpn.service` при активном `axata` — запуск пропущен по `ExecCondition`, соединение не переподключалось; `systemd-analyze verify` без замечаний; `tunnels-before-login` стоит в `After` у `greetd.service`.
- [x] 3.5 Агент: `amn-switch` — запрос к `ip.ru.net` возвращает адрес прямого выхода, отличный от ответа `api.ipify.org`.
- [x] 3.6 Проверка перезагрузкой (в журнале загрузки `Finished` у `awg-quick@amn0` и `axata-vpn` раньше запуска `greetd.service`, после входа значки зелёные) перенесена в `todo.md`, раздел «Открытые вопросы к пользователю».
- [x] 3.7 Проверка кликами (левый и правый клик по значкам: окно и меню открываются у трея и закрываются кликом вне них) перенесена в `todo.md`, раздел «Открытые вопросы к пользователю».

## 4. Спецификации и документация

- [x] 4.1 Дельты qs-tray-lang, hyprland-autostart, qs-network; `openspec validate tunnel-tray-autostart --strict`.
- [x] 4.2 `docs/amnezia-split-tunnel.md`, `docs/README.md`, `docs/host-state.md`, `system/amnezia/README.md`, `system/tunnels/README.md`.
