# Туннель AmneziaWG и выбор маршрута по адресу назначения

Трафик станции идёт тремя путями:

| Назначение | Путь |
|---|---|
| 10.200.0.0/16 | OpenVPN `axata` (соединение NetworkManager, `tun0`, маршрут из профиля через 10.200.5.254) |
| подсети США и Европы, адреса доменов из `domains.txt` | туннель AmneziaWG `amn0` на сервер Amnezia Premium |
| остальное | напрямую через `enp43s0`, шлюз 192.168.1.1 |

Почему так и что отвергнуто — запись
[`decisions/0009`](decisions/0009-amneziawg-split-by-destination.md).
Файлы лежат в `system/amnezia/` и `system/NetworkManager/conf.d/`, порядок
установки — [`../system/amnezia/README.md`](../system/amnezia/README.md).

## Устройство

- Пакеты `amneziawg-tools` (`awg`, `awg-quick`, юнит `awg-quick@.service`)
  и `amneziawg-go` (пользовательская реализация; модуля ядра нет, поэтому
  `awg-quick` запускает её сам) собраны из AUR. `amneziawg-tools` есть и в
  репозитории cachyos, но его пакет доступен только после полного обновления
  системы; при следующем `pacman -Syu` пакет можно перевести на репозиторий.
- Конфиг `/etc/amnezia/amneziawg/amn0.conf` (root, 0600) собирает
  `amn-export-config` из хранилища приложения
  (`~/.config/AmneziaVPN.ORG/AmneziaVPN.conf`, ключ `[Servers] serversList`,
  сервер `defaultServerId`, контейнер `awg`, поле `last_config` → `config`)
  и шаблона `amn0.conf.template`. Строка DNS отбрасывается, `Table = off`,
  `MTU = 1376` и `FwMark = 51820` задаёт шаблон. `AllowedIPs = 0.0.0.0/0`
  остаётся: это разрешение адресов для криптографической маршрутизации
  внутри туннеля, маршруты ядра от него не зависят.
- Ловушки `awg-quick`: `PostUp` — `amn-route up` (правило `fwmark 0x1
  lookup 100` с приоритетом 5100, маршрут по умолчанию через `amn0`
  в таблице 100, `rp_filter=2` только у `amn0`, затем таблица nftables —
  `amn-zones-update --if-stale`; метки начинают ставиться, когда маршрут
  для них уже есть), `PostDown` — `amn-route down` (снимает правило,
  таблицу 100 и таблицу nftables). Ловушки выполняются под `set -e`: отказ
  загрузки `nft -f` или команд `amn-route up` останавливает подъём, служба
  становится `failed`, а `amn-route` перед выходом снимает то, что успел
  поставить (`PostDown` после неудачного `PostUp` не вызывается). Ошибки
  скачивания и разрешения имён подъём не останавливают.
- Таблица `inet amn` (`amn.nft`), цепочка `output` типа `route`
  с приоритетом `mangle`: пакет с уже стоящей меткой не трогается
  (так проходят собственные пакеты туннеля с меткой 51820), пакет
  соединения с меткой conntrack 0x1 снова получает метку, адреса набора
  `bypass` (Endpoint туннеля, сервер OpenVPN, `bypass.txt`) и подсети
  10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 идут напрямую, новые
  соединения к адресам набора `zones` получают метку 0x1 и метку conntrack
  0x1. Соединение, установленное напрямую до того, как адрес попал
  в набор, остаётся прямым до закрытия: его адрес источника не подменён. После смены метки ядро
  заново выбирает маршрут — по правилу 5100 в таблицу 100. Цепочка
  `postrouting` подменяет адрес источника на адрес `amn0`: источник
  выбран ещё по таблице main.
- Набор `zones` — зоны ipdeny.com по кодам из `countries.txt` (США, ЕС-27,
  gb, ch, no, is, li) и адреса имён из `domains.txt`. Зоны кэшируются
  по странам в `/etc/amnezia/zones.d/` и собираются в `/etc/amnezia/zones.nft`;
  при подъёме туннеля они скачиваются заново, если `zones.nft` старше
  7 суток, таймера нет. Зона, которая не скачалась (в том числе оборванная
  по сроку), остаётся из прежнего кэша страны; неверные строки списков
  пропускаются с сообщением в журнале. Около 90 тыс. подсетей сливаются
  в наборе (`auto-merge`) примерно в 27 тыс. интервалов, загрузка занимает
  меньше секунды. Таблица заменяется одной транзакцией `nft -f`.
- Правила ufw (iptables-nft) не меняются: исходящий трафик ufw разрешает
  по умолчанию, ответы проходят по состоянию соединения. NetworkManager
  устройство `amn0` не трогает (`90-amn0-unmanaged.conf`).
- Соединению `axata` запрещён маршрут по умолчанию
  (`ipv4.never-default yes`), в таблицу main оно ставит только 10.200.0.0/16.
- Через туннель идёт трафик, порождённый на самой станции, в том числе
  rootless Docker (его сетью управляет процесс пользователя). Пересылаемый
  трафик (цепочка `forward`) не помечается.

## Автозапуск туннелей

Оба туннеля поднимает система при загрузке, до экрана входа; сессия
Hyprland VPN не поднимает (спецификация hyprland-autostart, требования
«Туннели при загрузке системы» и «Вход после туннелей»; устройство
и отвергнутые варианты — [`design.md`](../openspec/changes/archive/2026-11-02-tunnel-tray-autostart/design.md)
изменения OpenSpec tunnel-tray-autostart).

- `amn0` — служба `awg-quick@amn0.service` (`WantedBy=multi-user.target`,
  `After=network-online.target`). Подъём занимает около 14 с, из них 12 с —
  загрузка списков стран.
- `axata` — юнит `axata-vpn.service` (`system/tunnels/`): после
  `network-online.target` и сигнала NetworkManager о завершении запуска
  (`nm-online -s`) выполняет `nmcli --wait 60 connection up id axata` от
  root; пароль хранится в профиле, агент секретов не нужен. Уже активное
  соединение не переподключается (`ExecCondition`), после перезапуска
  NetworkManager юнит перезапускается вместе с ним (`PartOf`).
  Автоподключение самого NetworkManager для VPN не реализовано,
  а `connection.secondaries` при отказе VPN роняет проводное соединение,
  поэтому `connection.autoconnect` у `axata` остаётся `no`, а
  `connection.secondaries` пуст.
- `tunnels-before-login.service` стоит после обоих туннелей и перед
  `greetd.service`: экран входа и автовход ждут туннелей, поэтому herdr
  и браузеры, которые открывает демон workspaced, стартуют уже с ними.
  Предел ожидания — 90 с от начала загрузки (`JobTimeoutSec`, в него входит и ожидание сети): по нему systemd снимает
  только задание этого юнита, туннель продолжает подниматься, вход
  не задерживается.

Установка — `system/tunnels/install.sh files`, состояние —
`system/tunnels/install.sh status`. Порядок при загрузке:

```bash
journalctl -b -o short-monotonic -u awg-quick@amn0 -u axata-vpn \
    -u tunnels-before-login -u greetd | grep -E 'Starting|Finished|Started'
```

## Значки в трее

Сверху трея панели стоят значки `amn0` (󰖟) и `axata` (󰦝), состояние —
цветом: зелёный — поднят, жёлтый — поднимается, серый — не поднят,
красный — ошибка службы или последнего действия (спецификация
qs-tray-lang, требования «Значки туннелей» и следующие). Состояние
обновляется по событиям: `ip monitor link address` и журнал
`awg-quick@amn0` для `amn0`, общий поток `nmcli monitor` панели для
`axata`.

- Левый клик — окно сведений, прочитанных при открытии
  (`scripts/tunnelinfo` панели): для `amn0` — служба, адрес, endpoint,
  время последнего handshake, число элементов `zones`, возраст
  `zones.nft`, журнал службы; для `axata` — состояние, адрес `tun0`,
  маршрут 10.200.0.0/16, сервер, `axata-vpn.service`, журнал `nm-openvpn`.
- Правый клик — меню: `amn0` — запустить, остановить, перезапустить,
  обновить списки стран; `axata` — подключить, отключить, «Настройки»
  (`nm-connection-editor`).
- Пароль не спрашивается: команды root идут через `sudo -n` по правилу
  `/etc/sudoers.d/amn-switch` (состав — `system/amnezia/README.md`).

Проверка без мыши:

```bash
qs -c panel ipc call tunnels state        # состояние обоих туннелей, JSON
qs -c panel ipc call tunnels info amn0    # окно сведений (без захвата ввода)
qs -c panel ipc call tunnels run amn0 'Обновить списки стран'  # действие меню
qs -c panel ipc call tunnels shown        # содержимое открытого окна
qs -c panel ipc call tunnels close
```

## Ограничения

- DNS: имена разрешает systemd-resolved через 192.168.1.1, в том числе для
  доменов, трафик к которым идёт в туннель. Сервер DNS видит запрошенные
  имена; DNS туннеля (100.64.0.1) не используется.
- Список стран отражает регистрацию адресов, а не размещение: адреса CDN
  (Google, Amazon, Cloudflare) могут оказаться вне списков. Для таких
  сервисов нужное имя пишется в `domains.txt`; адреса разрешаются только
  при загрузке таблицы, смену адресов CDN между загрузками таблица
  не отслеживает. Поддомены не охватываются.
- IPv6 туннелем не обслуживается: глобального IPv6 на станции нет.

## Как добавить домен или адрес

1. Дописать имя в `system/amnezia/domains.txt` (адрес или подсеть, которые
   должны идти напрямую, — в `bypass.txt`; страну — кодом ipdeny в
   `countries.txt`).
2. `system/amnezia/install.sh files` — файлы ложатся в `/etc/amnezia`.
3. `sudo -A -p 'Перезагрузка наборов туннеля amn0' amn-zones-update --reload`
   (после правки `countries.txt` — `--force`).
4. Проверка: `nft get element inet amn zones '{ <адрес> }'`
   с правами root, `ip route get <адрес> mark 0x1`; размер набора —
   `amn-zones-update --count`.

## Как обновить списки стран

`sudo -A -p 'Обновление списков стран туннеля amn0' amn-zones-update --force`
— зоны скачиваются заново, таблица заменяется без перезапуска туннеля.
Без этого списки обновляются при первом подъёме туннеля после 7 суток.

## Как обновить конфиг после смены сервера в приложении

Приложение пишет новый конфиг в своё хранилище, `amn-export-config` его
переносит и сообщает, изменился ли файл:

```bash
sudo -A -p 'Перенос конфига AmneziaWG из приложения' amn-export-config
sudo -A -p 'Перезапуск туннеля amn0' systemctl restart awg-quick@amn0
```

## Если туннель не поднялся

1. `systemctl status awg-quick@amn0` и
   `journalctl -u awg-quick@amn0 -b` — строки `[#]` показывают, на какой
   команде остановился `awg-quick`; сообщения сценариев начинаются
   с `amn-zones-update:`.
2. `sudo -A -p '...' awg show amn0` — строка `latest handshake`: если её нет,
   сервер не отвечает (проверить `Endpoint`, сравнить конфиг с приложением
   через `amn-export-config`).
3. `ip rule` (строка 5100), `ip route show table 100`,
   `nft list table inet amn` с правами root — что из этого на месте.
4. Без туннеля станция работает напрямую: при `PostDown` правило и таблица
   снимаются, метки больше не ставятся.

## Как вернуть приложение AmneziaVPN

`system/amnezia/install.sh revert` выключает `awg-quick@amn0.service`
и включает `AmneziaVPN.service`; дальше туннель включается в окне
приложения. Kill switch приложения снова заблокирует OpenVPN `axata`.
Обратный переход — `sudo /usr/local/sbin/amn-switch` из терминала, без пароля
(порядок — [`../system/amnezia/README.md`](../system/amnezia/README.md)).
