## ADDED Requirements

### Requirement: Профили сети станции
У станции MUST быть два профиля сети. Основной: `awg-quick@amn0` и соединение NetworkManager `axata` с `ipv4.never-default yes`. Запасной, «всё через axata»: `awg-quick@amn0` остановлен, таблица `inet amn` и правило 5100 сняты, поднято `axata-full` — копия `axata` без `ipv4.never-default`, поэтому весь трафик станции идёт через `tun0`. Одновременно MUST быть активно не больше одного из соединений `axata` и `axata-full`.

#### Scenario: Запасной профиль поднят
- **WHEN** выбран запасной профиль и `net-profile backup` завершился успешно
- **THEN** `cat /etc/amnezia/profile` даёт `backup`, `systemctl is-active awg-quick@amn0` даёт `inactive`, `nmcli -t -f NAME connection show --active` содержит `axata-full` и не содержит `axata`, `ip -4 route get 1.1.1.1` показывает `dev tun0`

#### Scenario: Основной профиль поднят
- **WHEN** выбран основной профиль и `net-profile main` завершился успешно
- **THEN** файл профиля содержит `main`, `awg-quick@amn0` активен, активно `axata` без `axata-full`, `ip -4 route show default` не содержит `dev tun0`

#### Scenario: Копия соответствует оригиналу
- **WHEN** установлены оба профиля
- **THEN** `nmcli -g vpn.data connection show axata` и `nmcli -g vpn.data connection show axata-full` совпадают, `nmcli -g ipv4.never-default connection show axata-full` даёт `no`, `connection.autoconnect` равно `no`, `connection.secondaries` пусто

### Requirement: Файл профиля
Выбранный профиль MUST храниться в файле `/etc/amnezia/profile` (root, 0644) значением `main` или `backup`. Запасным профиль считается только при точном `backup`; отсутствие файла и любое другое содержимое означают основной.

#### Scenario: Файл отсутствует
- **WHEN** файла `/etc/amnezia/profile` нет
- **THEN** профиль основной, `systemctl start awg-quick@amn0` запускает службу

#### Scenario: Постороннее содержимое
- **WHEN** файл содержит `backup2`
- **THEN** профиль считается основным

### Requirement: Переход на запасной профиль
Вызов `/usr/local/sbin/net-profile backup` MUST выполнять шаги по порядку: проверки до изменений (root, `axata-full` существует, `tun0` свободен или принадлежит активному соединению); запись `backup` в файл профиля атомарно; остановка `awg-quick@amn0`; отключение `axata`, подъём `axata-full`; проверка запасного профиля. Если профиль уже запасной и проверка проходит, соединение MUST NOT переподключаться.

#### Scenario: Успешный переход
- **WHEN** основной профиль работает и пользователь выбирает «Запасной профиль: всё через axata»
- **THEN** пароль не спрашивается, `amn0` остановлен, `axata-full` поднят, проверка пройдена, итог содержит строки по каждому шагу

#### Scenario: Повторный вызов
- **WHEN** запасной профиль поднят и проверка проходит, а `net-profile backup` вызван снова
- **THEN** соединение `axata-full` не переподключается (его `connection.timestamp` не меняется), код выхода 0

### Requirement: Самодостаточность перехода
Во время перехода связи с внешним миром нет, поэтому до подъёма `axata-full` сценарий `net-profile` MUST NOT обращаться к удалённым ресурсам и MUST NOT зависеть от процессов сессии: его запускает пользователь из панели, и он доводит переход до конца сам.

#### Scenario: Закрытие панели во время перехода
- **WHEN** панель перезапускается во время `net-profile backup`
- **THEN** сценарий завершает переход и откат по собственным шагам, итог попадает в `/var/log/net-profile.log`

### Requirement: Журнал и одновременные вызовы
Сценарий `net-profile` MUST записывать итог построчно в стандартный вывод и в `/var/log/net-profile.log`. Одновременный второй вызов MUST отказывать сразу кодом 1, не ожидая.

#### Scenario: Итог в журнале
- **WHEN** `net-profile backup` завершился
- **THEN** последние строки `/var/log/net-profile.log` повторяют итог со статусом каждого шага

#### Scenario: Одновременный вызов
- **WHEN** во время работы `net-profile backup` запускается `net-profile main`
- **THEN** второй вызов завершается сразу кодом 1 с сообщением о том, что переход уже выполняется

### Requirement: Проверка запасного профиля
После подъёма `axata-full` сценарий MUST проверить: маршрут к адресу сервера OpenVPN идёт через `enp43s0`, а не через `tun0`; `ip -4 route get 1.1.1.1` идёт через `tun0`; таблицы `inet amn` нет и правила с приоритетом 5100 нет; запрос к `https://api.anthropic.com/` проходит и увеличивает счётчик приёма `tun0`; DNS соответствует требованию «DNS запасного профиля». Неудача любой проверки MUST вызывать откат по требованию «Откат перехода на запасной профиль».

#### Scenario: Маршрут к серверу OpenVPN
- **WHEN** запасной профиль поднят
- **THEN** `ip -4 route get 213.184.245.91` показывает `dev enp43s0`

#### Scenario: Отказ проверки
- **WHEN** `axata-full` поднят, но запрос к `api.anthropic.com` не проходит
- **THEN** сценарий откатывает переход, код выхода 1, итог содержит строку «ОШИБКА» с причиной

### Requirement: Возврат на основной профиль
Вызов `/usr/local/sbin/net-profile main` MUST выполнять шаги в таком порядке: проверки до изменений (root, `tun0` не занят посторонним процессом, конфиг `/etc/amnezia/amneziawg/amn0.conf` существует); запись `main` в файл профиля до запуска `awg-quick@amn0`; отключение `axata-full` и подъём `axata`; запуск `awg-quick@amn0`; проверка основного профиля.

#### Scenario: Порядок возврата
- **WHEN** выполняется `net-profile main`
- **THEN** в журнале `/var/log/net-profile.log` запись `main` в файл профиля стоит раньше запуска `awg-quick@amn0`, а запуск — после подъёма `axata`

### Requirement: Проверка основного профиля
После возврата сценарий MUST выполнить проверки туннеля из `amn-switch` (запрос к `api.anthropic.com` через `amn0` увеличивает счётчик приёма, адрес не входит в `zones` и `bypass`, метка 0x1 идёт в `amn0`), а также проверить прямой выход к `ya.ru`, маршрут 10.0.0.0/8 через `tun0` и отсутствие маршрута по умолчанию через `tun0`. Неудача любой проверки MUST вызывать откат по требованию «Откат возврата на основной профиль».

#### Scenario: Успешный возврат
- **WHEN** запасной профиль поднят, Amnezia отвечает, пользователь выбирает «Основной профиль»
- **THEN** `axata-full` не активно, `axata` активно, `awg-quick@amn0` активен, `curl --interface amn0 -sS https://ipinfo.io/json` отвечает

#### Scenario: Amnezia не отвечает
- **WHEN** сервер Amnezia не отвечает и вызывается `net-profile main`
- **THEN** проверка не проходит, станция остаётся в запасном профиле, `cat /etc/amnezia/profile` даёт `backup`, `ip -4 route get 1.1.1.1` показывает `dev tun0`, код выхода 1

### Requirement: Посторонний процесс на tun0
Если устройство `tun0` существует, а ни `axata`, ни `axata-full` не активны, оба вызова `net-profile` MUST отказывать до любых изменений кодом 3 и сообщением, что `tun0` занят посторонним процессом, с перечнем PID процессов `openvpn` только для сведения. Сценарий MUST NOT завершать чужие процессы.

#### Scenario: Ручной openvpn
- **WHEN** запущен `sudo openvpn --config axata.ovpn`, соединения NetworkManager не активны, и вызывается `net-profile backup`
- **THEN** код выхода 3, сообщение называет `tun0` и PID процесса `openvpn`, файл профиля, `awg-quick@amn0` и соединения не изменены, процесс `openvpn` работает

### Requirement: Откат перехода на запасной профиль
При неудаче `net-profile backup` MUST возвращаться состояние до вызова: прежнее содержимое файла профиля, `axata-full` отключён, `axata` поднят, `awg-quick@amn0` запущен, если был активен. Неудавшийся откат MUST попадать в итог строкой «ОШИБКА» и в журнал вместе с выводом `ip -4 route` и `nmcli -t -f NAME,DEVICE connection show --active`.

#### Scenario: Откат перехода на запасной профиль
- **WHEN** `axata-full` не поднялся при вызове `net-profile backup` из основного профиля
- **THEN** файл профиля содержит `main`, `awg-quick@amn0` активен, `axata` активно, код выхода 1

### Requirement: Откат возврата на основной профиль
При неудаче `net-profile main` станция MUST оставаться в запасном профиле: файл `backup`, `awg-quick@amn0` остановлен, `axata-full` поднят; итог MUST называть причину и сообщать, что профиль остался запасным. Неудавшийся откат MUST попадать в итог строкой «ОШИБКА».

#### Scenario: Amnezia не отвечает при откате
- **WHEN** проверка основного профиля не прошла, а `axata-full` не удалось поднять снова
- **THEN** итог содержит строку «ОШИБКА», код выхода 1

### Requirement: DNS запасного профиля
При запасном профиле имена MUST разрешаться так: на канале `tun0` стоят серверы, присланные сервером OpenVPN (10.200.115.1 и 10.200.115.2), и маршрут по умолчанию (`Default Route: yes`); на канале `enp43s0` остаются маршрутные домены `~ru ~by ~su ~xn--p1ai` и сервер 192.168.1.1. Значения MUST выставлять NetworkManager и systemd-resolved по профилю `axata-full`; `net-profile` MUST только проверять их и MUST NOT вызывать `resolvectl`.

#### Scenario: Имена в запасном профиле
- **WHEN** запасной профиль поднят
- **THEN** `resolvectl status tun0` показывает серверы 10.200.115.1 и 10.200.115.2 и `Default Route: yes`, `resolvectl domain enp43s0` содержит `~ru ~by ~su ~xn--p1ai`, `resolvectl query ya.ru` называет канал `enp43s0`

### Requirement: Права на переход
Пользователь станции MUST выполнять оба вызова без пароля через `sudo -n` по правилу `/etc/sudoers.d/amn-switch`, в которое входят ровно две новые команды: `/usr/local/sbin/net-profile backup` и `/usr/local/sbin/net-profile main`. Сценарий MUST лежать в `/usr/local/sbin` (владелец root, 0755), а любые другие аргументы MUST отклоняться и сценарием, и правилом.

#### Scenario: Вызов без пароля
- **WHEN** пользователь выполняет `sudo -n /usr/local/sbin/net-profile backup`
- **THEN** окно пароля не появляется

#### Scenario: Чужой аргумент
- **WHEN** пользователь выполняет `sudo -n /usr/local/sbin/net-profile foo`
- **THEN** sudo отказывает, не запуская сценарий

### Requirement: Смежные сценарии и профиль
`amn-switch` (переход с приложения AmneziaVPN) MUST ставить основной профиль: записывать `main` в файл профиля и отключать `axata-full`, если оно активно, до подъёма туннеля. `amn-apply-config` (смена страны) MUST при запасном профиле отказывать до любых изменений кодом 1 и сообщением, что страна меняется при основном профиле.

#### Scenario: Смена страны при запасном профиле
- **WHEN** файл профиля содержит `backup`, и `amn-apply-config` получает корректный конфиг
- **THEN** `amn0.conf` и `country.json` не изменены, код выхода 1, сообщение называет запасной профиль
