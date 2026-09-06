## Context

Монолитные `eww.yuck`/`eww.scss` и плоский `scripts/` (см. proposal.md — Why). Ограничения, определяющие решение:

- eww умеет текстовую сборку конфига из файлов: `(include "./path.yuck")` в разметке и `@import` в scss (компилятор grass); путь include отсчитывается от корня конфигурации.
- Рабочий каталог всех запускаемых eww команд (poll, onclick, deflisten) равен каталогу конфигурации — относительные пути вида `widgets/<имя>/скрипт` работают без обёрток.
- Конфиг разворачивается chezmoi: префиксы исходников (`executable_`, `dot_`) действуют на любом уровне вложенности.
- Часть скриптов резолвит соседей через `dirname "$0"` (network-sync→network, apps-update→apps-list, apps-list→appicon) — это переносимо только если соседи переезжают вместе.

## Goals / Non-Goals

**Goals:**

- Самодостаточные папки виджетов: правка одного виджета не требует открытия общих файлов.
- Тонкие точки сборки: главный yuck/scss содержат только глобал, композицию и окна верхнего уровня.
- Нулевое изменение поведения: дашборд после миграции визуально и функционально идентичен.

**Non-Goals:**

- Переписывание логики скриптов, рефакторинг стилей, смена палитры.
- Введение этапа сборки (make/скрипты генерации) или переход на новый формат конфигов eww.
- Разбиение уже выделенных возможностей (specs) на более мелкие.

## Decisions

### 1. Механизм сборки — нативные `(include)` и `@import`

Главный `eww.yuck` подключает модули строками вида `(include "./widgets/clock/clock.yuck")`; `eww.scss` оставляет себе `*`-сброс, переменные Tokyo Night, `.tile`, `.tile-title`, стили окон и собирает виджеты через `@import 'widgets/clock/clock';`.

Альтернативы: генерация склейки шаблонами chezmoi — отвергнуто (усложняет деплой, ломает навигацию по файлам); оставить монолит — противоречит цели. Нативный include не добавляет зависимостей и работает с `eww reload`.

### 2. Одна папка — один `<имя>.yuck` + один `<имя>.scss` (+ `scripts/`)

Единое правило вместо «файл на defwidget»: в папке виджета лежат его разметка (defwidget + его poll/listen/var + при необходимости его defwindow), стили и скрипты. Итоговая структура:

```
dot_config/eww/
├── eww.yuck            # include-блок, композиция dash, defwindow dashboard
├── eww.scss            # глобал: сброс, палитра, .tile/.tile-title, @import
├── scripts/            # только общие: appicon, popup
└── widgets/
    ├── clock/       clock.yuck, clock.scss, scripts/calendar
    ├── weather/     weather.yuck, weather.scss, scripts/weather
    ├── gauges/      gauges.yuck, gauges.scss, scripts/{cpu,cputemp,ram,gpu,gputemp}
    ├── volume/      volume.yuck, volume.scss, scripts/volume
    ├── network/     network.yuck, network.scss, scripts/{network,network-listen,network-sync,netmenu-items}
    ├── disks/       disks.yuck, disks.scss, scripts/disks
    ├── favorites/   favorites.yuck, favorites.scss
    ├── workspaces/  workspaces.yuck, workspaces.scss, scripts/workspace
    ├── launcher/    launcher.yuck, launcher.scss, scripts/{apps-list,apps-update}
    └── power/       power.yuck, power.scss
```

Шкалы CPU/RAM/GPU — один компонент `gauges`: три плитки повторяют одну разметку-паттерн и делят классы `.gauge-tile`/`.t-*`; три отдельные папки размазали бы общие стили и скрипты. Альтернатива (папка на каждую плитку) отвергнута ради цельности общего стиля шкал.

Окно `netmenu` объявляется в `widgets/network/network.yuck` рядом со своим poll `netmenu-content`; окно `dashboard` остаётся в главном файле — это каркасный объект уровня шелла (геометрия, struts, windowtype).

### 3. Poll'ы следуют за единственным потребителем

Каждая переменная используется ровно одной плиткой (проверено по `eww.yuck`), поэтому defpoll переезжает в файл потребителя без исключений. Скрытая ссылка `network-sync` (`label :visible false`) переезжает вместе с network-tile в тот же файл — страховка опроса сохраняется по построению.

### 4. Резолвинг общего соседа: своя папка → корневой `scripts/`

Общие скрипты (`appicon`, `popup`) остаются в корне `scripts/`. Скрипты, ищущие соседей через `$DIR`, получают второй фолбэк на корневой каталог (три уровня вверх: `widgets/<имя>/scripts/` → корень конфигурации):

- `widgets/launcher/scripts/apps-list` и `widgets/workspaces/scripts/workspace` ищут appicon как `$DIR/appicon` → `$DIR/executable_appicon` → `$DIR/../../../scripts/(executable_)appicon`;
- `popup` вызывает переехавший `netmenu-items` по новому пути `widgets/network/scripts/netmenu-items`; его self-call `scripts/popup …` и onclick-строки `netmenu-items` остаются валидными (popup не двигается).

### 5. Пути запуска — от корня конфигурации

Команды в poll/onclick записываются как `widgets/<имя>/scripts/<скрипт>` без абсолютных путей и обёрток: cwd гарантируется самим eww. Это же правило фиксирует спека eww-shell (ADDED «Модульная структура конфигурации»).

### 6. Миграция по одному виджету с пилотом

Первым переезжает `favorites` (нет скриптов, минимальные стили) — пилот проверяет механику include/@import до массового переноса. Затем остальные виджеты, `network` последним (тянет правки `popup`). Главные файлы чистятся в конце, когда все блоки ушли.

## Risks / Trade-offs

- [Версия eww не поддерживает `(include)` или grass не понимает относительный `@import`] → пилотный шаг с одним виджетом выявляет это в первые минуты; откат — `git checkout`. Фолбэк-план: склейка на этапе деплоя шаблоном chezmoi (решение 1 меняется, структура папок сохраняется).
- [`eww reload` может не подобрать новые файлы без перезапуска демона] → на каждом шаге верифицировать `eww kill && eww daemon && eww open dashboard`, а не полагаться только на reload.
- [Потеря или искажение блоков при переносе] → блоки перемещаются дословно (copy-paste, без редактирования); контроль — `grep -c 'defwidget\|defpoll\|deflisten'` до/после совпадает, поведение сверяется визуально.
- [Скрытые перекрёстные ссылки останутся незамеченными] → после миграции `grep -rn 'scripts/' dot_config/eww --include='*' | grep -v widgets/` обязан показать только: общий `scripts/appicon`, `scripts/popup`, вызовы popup из volume/network и self-call внутри самого popup.
- [Двойное обслуживание при частичном переносе] → изменение коммитится одним атомарным набором; между шагами конфиг работоспособен, но правки в старые локации запрещены до конца миграции.

## Migration Plan

1. Пилот `favorites`: создать папку, перенести defwidget и стили, добавить include/@import, `eww reload` + визуальная проверка.
2. Перенос остальных виджетов в порядке: clock → weather → gauges → volume → disks → workspaces → launcher → power → network; после каждого — перезапуск демона и проверка плитки.
3. Правка `popup` (путь к `netmenu-items`) и фолбэка appicon в `apps-list`.
4. Чистка главных файлов: удаление перенесённых блоков из `eww.yuck`/`eww.scss`.
5. Контрольные проверки: grep-контроль ссылок (см. Risks), `eww reload`, полный обход плиток, фокус в лаунчере, netmenu, громкость; `chezmoi apply` и проверка развёрнутого `~/.config/eww`.

Откат на любом шаге — `git checkout -- dot_config/eww`.

## Open Questions

(none)
