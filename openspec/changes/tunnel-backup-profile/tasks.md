## 1. Профиль NetworkManager

- [ ] 1.1 `system/tunnels/install.sh`: действие `profile` — `nmcli connection clone axata axata-full`, `ipv4.never-default no`, `connection.autoconnect no`; повторный запуск пересоздаёт `axata-full` из `axata`, отказ, пока `axata-full` активен
- [ ] 1.2 `install.sh status`: вывод `axata-full` (активность, `never-default`) и расхождение `vpn.data` с `axata`
- [ ] 1.3 Проверка: `nmcli -g vpn.data connection show axata` и `axata-full` совпадают, `nmcli -s -g vpn.secrets connection show axata-full` непусто (пароль скопирован), `nmcli -g ipv4.never-default connection show axata-full` даёт `no`

## 2. Сценарий `net-profile`

- [ ] 2.1 `system/tunnels/net-profile`: вызовы `backup` и `main`, другие аргументы — отказ; замок `flock -n /run/net-profile.lock` с комментарием (какой ресурс, почему иначе нельзя, без ожидания); журнал `/var/log/net-profile.log`, итог построчно
- [ ] 2.2 Проверки до изменений и отказ кодом 3 при постороннем процессе на `tun0` (без завершения процессов)
- [ ] 2.3 Порядок шагов `backup` и `main`, запись файла профиля атомарно и до запуска `awg-quick@amn0`, проверка по требованиям «Проверка запасного профиля» и «Проверка основного профиля»
- [ ] 2.4 Откат по требованиям «Откат перехода на запасной профиль» и «Откат возврата на основной профиль»; повторный вызов в том же профиле без переподключения
- [ ] 2.5 `install.sh files` (оба каталога) ставит сценарий в `/usr/local/sbin` (root, 0755)
- [ ] 2.6 `shellcheck` и `shfmt -d` по затронутым сценариям

## 3. Загрузка

- [ ] 3.1 `system/tunnels/awg-quick@amn0.service.d/10-profile.conf` (`ExecCondition`), установка в `/etc/systemd/system/awg-quick@amn0.service.d`
- [ ] 3.2 `system/tunnels/axata-vpn.service`: `ExecCondition` на оба соединения, `ExecStart` по файлу профиля
- [ ] 3.3 `systemd-analyze verify` обоих юнитов; `tunnels-before-login.service` без изменений (проверка — порядок `After=`)

## 4. Права

- [ ] 4.1 `system/sudo/sudoers.d/amn-switch`: `net-profile backup` и `net-profile main` с точными аргументами, комментарий в шапке; `visudo -c -f`
- [ ] 4.2 `sudo -n -l` показывает обе команды и не показывает `net-profile` с другими аргументами

## 5. Смежные сценарии

- [ ] 5.1 `system/amnezia/amn-switch`: запись `main` в файл профиля и отключение `axata-full` до подъёма туннеля
- [ ] 5.2 `system/amnezia/amn-apply-config`: отказ кодом 1 при запасном профиле до любых изменений

## 6. Панель

- [ ] 6.1 `scripts/tunnelstate`: поля `profile` и `connection`; `axata` — по активному из двух соединений, иначе по файлу; `uuid` активного профиля
- [ ] 6.2 `Tunnels.qml`: регулярное выражение `inotifywait` дополняется `profile$` (чтение обоих туннелей); действие смены профиля с занятостью обоих значков и ошибкой обоих
- [ ] 6.3 `tiles/Tray.qml`: пункты меню смены профиля; меню `amn0` при запасном профиле — только «Основной профиль»; «Отключить», «Подключить» и «Настройки» для соединения активного профиля; цель IPC `state` с полями профиля
- [ ] 6.4 Подсказки и серый значок `amn0` при запасном профиле; `scripts/tunnelinfo`: строки «Профиль», «Соединение», «Маршрут по умолчанию», «DNS»
- [ ] 6.5 Проверка без мыши: `qs -c panel ipc call tunnels state` (поле `profile`), `tunnels info axata`, `tunnels shown`; `chezmoi apply`, перезапуск панели, в журнале нет ошибок QML

## 7. Документы

- [ ] 7.1 `docs/decisions/0011-network-backup-profile.md` (новая запись по правилам README каталога: профиль `axata-full`, файл профиля, ручной переход, отвергнутое `never-default` у одного профиля), строка в перечне README, ссылка из `docs/amnezia-split-tunnel.md`
- [ ] 7.2 `docs/amnezia-split-tunnel.md`: раздел о профилях (устройство, DNS, переход из панели и терминала, проверка командами), правка разделов «Автозапуск туннелей» и «Значки в трее»
- [ ] 7.3 `system/amnezia/README.md`, `system/tunnels/README.md` (таблица файлов, `install.sh profile`), `system/sudo/README.md` (две новые команды и полный нынешний состав правила)
- [ ] 7.4 `dot_claude/CLAUDE.md`, раздел «Повышение привилегий»: в перечень без пароля — `net-profile backup` и `net-profile main`; затем `chezmoi apply` для `~/.claude/CLAUDE.md`
- [ ] 7.5 Проверка текста: поиск по `docs/`, `system/` и `openspec/specs/` формулировок, ставших неверными (`axata` как единственное соединение, перечень правила sudoers)

## 8. Живое переключение (выполняет пользователь из панели)

- [ ] 8.1 Остановить ручной `openvpn` (иначе отказ кодом 3); установка: `system/tunnels/install.sh files`, `system/tunnels/install.sh profile`, `system/amnezia/install.sh files`
- [ ] 8.2 Меню «Запасной профиль: всё через axata»: `ip -4 route get 1.1.1.1` (`dev tun0`), `ip -4 route get 213.184.245.91` (`dev enp43s0`), `resolvectl status tun0` (серверы и `Default Route: yes`), `resolvectl domain enp43s0`, `tunnels state`; при расхождении DNS с D7 — уточнить design.md и требование
- [ ] 8.3 Перезагрузка в запасном профиле: `awg-quick@amn0` `inactive`, `axata-full` активно, вход не задержан
- [ ] 8.4 Меню «Основной профиль» (когда Amnezia отвечает): `amn0` и `axata` подняты, `ip -4 route show default` без `tun0`, проверка `amn-switch`-типа пройдена
- [ ] 8.5 `openspec validate tunnel-backup-profile --strict`, затем `openspec archive tunnel-backup-profile -y`
