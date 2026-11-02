# Автозапуск туннелей (`/etc/systemd/system`)

Устройство — [`docs/amnezia-split-tunnel.md`](../../docs/amnezia-split-tunnel.md),
раздел «Автозапуск туннелей»; выбор способа —
[`design.md`](../../openspec/changes/archive/2026-11-02-tunnel-tray-autostart/design.md)
изменения OpenSpec tunnel-tray-autostart.

| Файл | Куда ставится | Что это |
|---|---|---|
| `axata-vpn.service` | `/etc/systemd/system`, включается в `multi-user.target` | подъём VPN `axata` от root после готовности сети и после перезапуска NetworkManager |
| `tunnels-before-login.service` | `/etc/systemd/system`, включается в `greetd.service.wants` | экран входа ждёт `awg-quick@amn0` и `axata-vpn` не дольше 105 с от начала загрузки |
| `install.sh` | не ставится | установка и состояние |

```bash
system/tunnels/install.sh files    # права root спрашивает окно askpass
system/tunnels/install.sh status
```

Повторная установка безопасна: активное соединение `axata` юнит
не переподключает. Откат —
`sudo -A -p 'Откат автозапуска туннелей' systemctl disable axata-vpn.service tunnels-before-login.service`.
