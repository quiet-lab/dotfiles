## Why

Легаси-виджеты (нижний бар, календарь-popup, powermenu) дублируют функциональность нового вертикального дашборда и остаются в конфиге мёртвым кодом: запланированное их удаление («задача 8.1» исчезнувшего change `add-eww-dashboard`) так и не было выполнено. Чистка до создания спецификаций позволит описать целевое состояние системы без оглядки на удаляемое.

## What Changes

- **BREAKING**: удалены окна eww `bar` (нижняя панель) и `calendar` (popup-календарь).
- Удалены легаси-виджеты: `launcher`, `wifi`, `volum`, `control`, `time`, `cal`, `power`, `left`, `right`, `bar` и неиспользуемый заглушечный виджет `stub`.
- Удалены легаси-переменные: poll'ы `wifi-icon`, `wifi-name`, `calendar_day`, `calendar_month`, `calendar_year`; переменные `volum`, `power`.
- Из `scripts/popup` удалены ветки-сироты, вызывавшиеся только из легаси-виджетов: `launcher` (rofi), `wifi` (nmtui), `calendar`.
- Из `eww.scss` удалены стили легаси (~190 строк): `.eww_bar`, `.control`, `.powermenu`, `.cal-box`, `.time`, `.button-*` и связанные.
- Обновлена шапка `eww.yuck`: убрана ссылка на несуществующую спеку `openspec/changes/add-eww-dashboard`.

Сохраняются без изменений (используются дашбордом, не легаси):

- виджет `workspaces` и его deflisten `workspace`;
- окно `netmenu` и переменная `netmenu-content`;
- volume-tile и все скрипты данных (`cpu`, `ram`, `gpu`, `disks`, `weather`, `appicon`, `apps-list`…);
- ветки `audio` и `netmenu*` скрипта `popup`.

## Capabilities

### New Capabilities

(none — целевые спецификации будут созданы отдельными изменениями после чистки)

### Modified Capabilities

(none — легаси никогда не был специфицирован; каталог `openspec/specs/` пуст. Изменение задаёт `skip_specs: true`.)

## Impact

- `dot_config/eww/eww.yuck`: −~180 строк (легаси-виджеты, окна, дублирующие poll'ы).
- `dot_config/eww/eww.scss`: −~190 строк; риск: глобальные селекторы `scale` / `scale trough` обслуживают и полосу громкости (`volbar`) дашборда — удалять точечно.
- `dot_config/eww/scripts/executable_popup`: удаление трёх веток-сирот.
- Верификация ручная: `eww reload`, визуальная проверка всех плиток, фокус в поле поиска лаунчера, работа netmenu.
