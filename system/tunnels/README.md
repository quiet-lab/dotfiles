# Автозапуск туннелей и профили сети (`/etc/systemd/system`, `/usr/local/sbin`)

Устройство — [`docs/amnezia-split-tunnel.md`](../../docs/amnezia-split-tunnel.md),
разделы «Автозапуск туннелей» и «Профили сети»; выбор способа автозапуска —
[`design.md`](../../openspec/changes/archive/2026-11-02-tunnel-tray-autostart/design.md)
изменения OpenSpec tunnel-tray-autostart, запасного профиля — запись
[`docs/decisions/0011`](../../docs/decisions/0011-network-backup-profile.md).

| Файл | Куда ставится | Что это |
|---|---|---|
| `axata-vpn.service` | `/etc/systemd/system`, включается в `multi-user.target` | подъём от root соединения профиля сети (`axata` или `axata-full`) после готовности сети и после перезапуска NetworkManager |
| `tunnels-before-login.service` | `/etc/systemd/system`, включается в `greetd.service.wants` | экран входа ждёт `awg-quick@amn0` и `axata-vpn` не дольше 105 с от начала загрузки |
| `awg-quick@amn0.service.d/10-profile.conf` | `/etc/systemd/system/awg-quick@amn0.service.d` | при запасном профиле сети `awg-quick@amn0` не запускается (условие запуска) |
| `net-profile` | `/usr/local/sbin` (root, 0755) | переход между профилями сети: `net-profile backup`, `net-profile main` |
| `tests/net-profile.sh` | не ставится | проверка логики `net-profile` на подставных командах, без root |
| `install.sh` | не ставится | установка, соединение `axata-full`, состояние |

```bash
system/tunnels/install.sh files     # права root спрашивает окно askpass
system/tunnels/install.sh profile   # axata-full из axata; повторный запуск пересоздаёт
system/tunnels/install.sh status
system/tunnels/tests/net-profile.sh
```

Правило sudoers для `net-profile` ставит `system/amnezia/install.sh files`.
Повторная установка безопасна: активное соединение `axata` или
`axata-full` юнит не переподключает. Откат автозапуска —
`sudo -A -p 'Откат автозапуска туннелей' systemctl disable axata-vpn.service tunnels-before-login.service`.
