## 1. Код

- [x] 1.1 `Tunnels.qml`: поток журнала `axata-vpn.service` (D1), сохранение ошибки поднятого туннеля и процессы действий по туннелю (D2), имя туннеля в предупреждении потока.
- [x] 1.2 `tiles/Tray.qml`: меню `amn0` при активной службе (D3), повторный клик и чтение сведений (D4), «выполняется действие» в подсказке, IPC `run` возвращает отказ, без команды `menu`.
- [x] 1.3 `scripts/tunnelinfo`: поле `tunnel`, строки журнала обрезаются по знакам.
- [x] 1.4 `tunnels-before-login.service`: `JobTimeoutSec=105` (D5), установлено `system/tunnels/install.sh files`.

## 2. Проверка

- [x] 2.1 Агент: перезапуск панели без ошибок QML; IPC `info amn0` и сразу `info axata` — показано окно `axata`; `state` — оба `up`; потоков `journalctl -f` два, `nmcli monitor` один.
- [x] 2.2 Проверка кликами и перезагрузкой — в `todo.md` (пункты изменения tunnel-tray-autostart).

## 3. Спецификации и документация

- [x] 3.1 Дельты qs-tray-lang и hyprland-autostart, `openspec validate tunnel-tray-fixes --strict`.
- [x] 3.2 `docs/amnezia-split-tunnel.md`, `system/tunnels/README.md`.
