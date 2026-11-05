# Туннель AmneziaWG (`/etc/amnezia`, `/usr/local/sbin`)

Устройство, ограничения и порядок починки — [`docs/amnezia-split-tunnel.md`](../../docs/amnezia-split-tunnel.md),
решение — [`docs/decisions/0009`](../../docs/decisions/0009-amneziawg-split-by-destination.md).

| Файл | Куда ставится | Что это |
|---|---|---|
| `amn-export-config` | `/usr/local/sbin` | сборка `amn0.conf` из хранилища AmneziaVPN и шаблона; при выгрузке удаляет `country.json`; если страна выбрана в панели, `install.sh` и `amn-switch` вызывают его с `--rerender` — нынешний конфиг заново подставляется в шаблон |
| `amn-apply-config` | `/usr/local/sbin` | установка конфига страны из стандартного ввода (JSON от `amn-country set`): проверка по шаблону, перезапуск, откат |
| `awg-quick@amn0.service.d/50-log-verbose.conf` | `/etc/systemd/system/awg-quick@amn0.service.d` | подробный журнал amneziawg-go для состояния «связи нет» в трее |
| `amn-zones-update` | `/usr/local/sbin` | загрузка таблицы nftables `inet amn` с наборами |
| `amn-route` | `/usr/local/sbin` | правило метки, таблица 100 и DNS канала для зон за туннелем (ловушки `awg-quick`) |
| `amn-switch` | `/usr/local/sbin` | переход с приложения на `awg-quick@amn0` с проверкой и откатом |
| `../sudo/sudoers.d/amn-switch` | `/etc/sudoers.d` (0440) | без пароля: `amn-switch`, `systemctl start/stop/restart awg-quick@amn0`, `awg show amn0 endpoints`, `awg show amn0 latest-handshakes`, `amn-zones-update --count` и `--force`, `amn-apply-config` без аргументов (значок `amn0` в трее панели) |
| `install.sh` | не ставится | установка файлов, переход, возврат, состояние |
| `amn0.conf.template` | `/etc/amnezia` | шаблон конфига без ключей |
| `amn.nft` | `/etc/amnezia` | таблица `inet amn` без элементов наборов |
| `countries.txt`, `domains.txt`, `bypass.txt` | `/etc/amnezia` | страны, домены и адреса напрямую |
| `../NetworkManager/conf.d/90-amn0-unmanaged.conf` | `/etc/NetworkManager/conf.d` | NetworkManager не управляет `amn0` |

Сценарии выполняются от root из ловушек `awg-quick`, поэтому лежат
в `/usr/local/sbin`, а не в `~/.local/bin/handmade-scripts`: код, который
исполняет root, не должен быть доступен на запись пользователю.

Пакеты (собираются из AUR, установка — `pacman -U`):

```bash
paru -G amneziawg-tools amneziawg-go
(cd amneziawg-tools && makepkg)
(cd amneziawg-go && mise exec go@latest -- makepkg -d)   # Go только на время сборки
sudo -A -p 'Установка amneziawg-tools и amneziawg-go' pacman -U --noconfirm \
    amneziawg-tools/*.pkg.tar.zst amneziawg-go/*.pkg.tar.zst
```

Переход с приложения — сценарий `amn-switch`, его запускает пользователь
в терминале: пока туннель приложения снят, а свой ещё не поднят, станция
не достаёт до сервисов за туннелем, и агент этот шаг выполнить не может.
Файлы сначала ставит `install.sh files` (права root спрашивает окно
askpass); затем сценарий без пароля (правило `sudoers.d/amn-switch`) выключает
`AmneziaVPN.service`, поднимает `awg-quick@amn0` и `axata`, проверяет
результат и при отказе туннеля возвращает прямой выход; журнал —
`/var/log/amn-switch.log`, повторный запуск безопасен:

```bash
system/amnezia/install.sh files
sudo /usr/local/sbin/amn-switch
system/amnezia/install.sh status
```

Ключ `--signal` после подъёма `axata` даёт сигнал duty `studio-tunnel-up`
от пользователя, запустившего `sudo`.

Возврат приложения — `system/amnezia/install.sh revert`.

Автозапуск `axata` при загрузке и ожидание туннелей перед экраном входа —
`../tunnels/` ([`README.md`](../tunnels/README.md)).
