## 1. eww.yuck — удаление легаси

- [x] 1.1 Обновить шапку файла: убрать строку «Спека: openspec/changes/add-eww-dashboard» и упоминание задачи 8.1; проверить, что комментарий отражает реальность (только дашборд + netmenu)
- [x] 1.2 Удалить окна `bar` и `calendar` (defwindow) — проверить, что окно `netmenu` осталось
- [x] 1.3 Удалить виджеты `launcher`, `wifi`, `volum`, `control`, `time`, `cal`, `power`, `left`, `right`, `bar` и их defvar (`volum`, `power`) — НЕ тронуть `workspaces`/deflisten `workspace`
- [x] 1.4 Удалить легаси poll'ы `wifi-icon`, `wifi-name`, `calendar_day`, `calendar_month`, `calendar_year`; сверить, что дубли календаря дашборда (`cal-day/month/year`) на месте
- [x] 1.5 Удалить неиспользуемый виджет `stub`; убедиться, что `dash` и `dashboard` на него не ссылаются
- [x] 1.6 Запустить `eww reload`: парсер не ругается на отсутствующие переменные/виджеты; колонка плиток визуально без изменений (часы, погода, шкалы, громкость, сеть, диски, избранное, столы, лаунчер, питание); поле поиска лаунчера получает фокус

## 2. eww.scss — удаление легаси-стилей

- [x] 2.1 Удалить блоки: `.eww_bar`, `.launcher_icon`, `.control`, `.wifi-icon` (легаси), `.time`, `.time-sep` (глобальный), `.cal-box` + вложенный `.cal-inner-box`, селекторы `calendar:*` вне `.clock-tile`, `.powermenu`, `.button-wmres/.button-reb/.button-lock/.button-quit/.button-off` — стили `.clock-tile .time-*` и `.clock-tile calendar` оставить
- [x] 2.2 Удалить глобальные `scale { min-width: 90px }`, `scale trough { ... }`, `.volbar trough highlight { ... }`; tile-версии в `.volume-tile` и `.disks-tile .disk-bar` остались нетронутыми
- [x] 2.3 Запустить `eww reload` и осмотреть: полоса громкости заполнена зелёным и растянута по ширине плитки; полосы дисков нормальной ширины (не сжались после удаления `min-width`); цвета шкал CPU/RAM/GPU и температурные классы не изменились

## 3. scripts/popup — ветки-сироты

- [x] 3.1 Удалить ветки `launcher)`, `wifi)`, `calendar)` и функцию `calendar()`; ветки `audio`, `netmenu`, `net-close`, `wifi-rescan`, `wifi-toggle`, `vpn-up`, `vpn-down`, `eth-down` остались
- [x] 3.2 Проверить действием: кнопка динамика открывает pavucontrol; «⋮» в плитке сети открывает netmenu, пункты «Поиск сетей Wi-Fi» / «Выключить Wi-Fi» отрабатывают и закрывают меню

## 4. Финальная верификация и коммит

- [x] 4.1 Полный чеклист за один проход: все 10 плиток живые; клики питания требуют подтверждения намерения (lock/logout/restart/off — только навести и убедиться, что тултипы на месте); netmenu открывается/закрывается; нижнего бара больше нет (`eww active-windows` не содержит `bar` и `calendar`)
- [x] 4.2 Закоммитить всё одним коммитом; при проблемах — `git revert` и повторный проход по чеклисту
