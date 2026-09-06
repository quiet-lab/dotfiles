## Why

Конфигурация EWW-дашборда — монолит: все 11 виджетов описаны в одном `eww.yuck` (268 строк), все стили в одном `eww.scss` (526 строк), а 18 скриптов лежат плоско в `scripts/` без видимой привязки к виджетам. Правка или добавление одного виджета требует чтения и правки общих файлов целиком, принадлежность скрипта плитке приходится восстанавливать по содержимому.

## What Changes

- Разбиение разметки: каждый виджет (`defwidget` + относящиеся к нему `defpoll`/`deflisten`/`defvar`) переезжает в собственную папку `dot_config/eww/widgets/<имя>/`; главный `eww.yuck` собирает их через `(include ...)`.
- Разбиение стилей: стили виджета переезжают в его папку; главный `eww.scss` оставляет себе глобальные переменные Tokyo Night, сброс и базовые стили, подключая остальные через `@import`.
- Перенос скриптов: скрипты, нужные одному виджету, лежат рядом с ним (`widgets/<имя>/…`); общие для нескольких виджетов (`appicon`, `popup`) остаются в корневом `scripts/`.
- Состав папок: `clock` (включая `scripts/calendar`), `weather`, `gauges` (cpu/ram/gpu — три плитки одного компонента с общей стилистикой шкал, скрипты cpu/cputemp/ram/gpu/gputemp), `volume`, `network` (плитка + окно netmenu + скрипты network/network-listen/network-sync/netmenu-items), `disks`, `favorites`, `workspaces`, `launcher`, `power`.
- Обновление всех ссылок на перенесённые пути: команды poll/deflisten, `onclick`, перекрёстные вызовы скриптов (`popup` ↔ `netmenu-items`), упоминания путей в спецификациях.
- **Поведение дашборда не меняется**: состав колонки, окна, интервалы опросов, действия кнопок и внешний вид сохраняются дословно.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `eww-shell`: новое требование о модульной структуре конфигурации (папка `widgets/`, include-сборка yuck, @import-сборка scss, размещение общих и виджетных скриптов).
- `eww-clock-calendar`: требование «Календарь» — путь `scripts/calendar` → `widgets/clock/scripts/calendar`.
- `eww-monitors`: требования «Загрузка CPU» и «Плитка дисков» — новые пути скриптов `widgets/gauges/scripts/*`, `widgets/disks/scripts/disks`.
- `eww-network`: требования «Реактивное обновление» и «Пункты меню» — новые пути `widgets/network/scripts/*` (`scripts/popup` остаётся на месте).
- `eww-launcher`: требование «Фильтр по подстроке» — новый путь `widgets/launcher/scripts/apps-update`.

Примечание: у `eww-weather` и `eww-workspaces` путь скрипта упоминается только в разделе Purpose — он актуализируется при синхронизации спек без изменения требований.

## Impact

- `dot_config/eww/eww.yuck`: сокращается до include-блока, композиции `dash` и окна `dashboard`; `dot_config/eww/eww.scss` — до глобала и импортов (~15% текущего объёма).
- ~20 новых файлов под `dot_config/eww/widgets/` (chezmoi-префиксы `executable_` сохраняются во вложенных папках).
- Точки интеграции: cwd запускаемых eww команд равен каталогу конфигурации, поэтому пути вида `widgets/<имя>/скрипт` работают в poll/onclick без обёрток; скрипты, резолвящие соседей через `dirname "$0"` (network-sync→network, apps-update→apps-list), перенос не замечают.
- Верификация ручная: `eww reload`, визуальная проверка всех плиток, фокус в поле лаунчера, работа netmenu и громкости.
