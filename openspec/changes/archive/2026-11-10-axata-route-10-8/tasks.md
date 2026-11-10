## 1. Код и профиль

- [x] 1.1 `scripts/tunnelinfo`: строка и запрос маршрута 10.0.0.0/8.
- [x] 1.2 Профиль `axata`: `nmcli connection modify axata -ipv4.routes "10.200.0.0/16 10.200.5.254"`, маршрут в живой таблице удалён без переподключения.

## 2. Проверка

- [x] 2.1 Агент: таблица main, достижимость 10.200.5.254, IPC `info axata` и `shown`, `state`.

## 3. Спецификации и документация

- [x] 3.1 Дельта qs-tray-lang, `openspec validate axata-route-10-8 --strict`.
- [x] 3.2 `docs/amnezia-split-tunnel.md`.
