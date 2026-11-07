## MODIFIED Requirements

### Requirement: Индикатор цепочки с выходом
Панель Quickshell MUST показывать индикатор, пока открыта цепочка с выходом (спецификация ws-config, «Цепочки с выходом») или режим многозвенной цепочки (спецификация ws-config, «Цепочки клавиш и привязки»): оба живут в подкартах с префиксом `ws-sticky:`, и индикатор MUST показывать их одинаково. Состояние индикатора MUST определяться событием Hyprland `submap`: имя подкарты с префиксом `ws-sticky:` показывает индикатор для этого состояния, пустое имя и любое другое имя скрывают его. Опрашивать композитор или демон по времени панель MUST NOT.

#### Scenario: Вход, переход и выход
- **WHEN** выполнена `hyprctl eval 'hl.dispatch(hl.dsp.submap("ws-sticky:apps"))'`, затем то же для `ws-sticky:apps/raise`, затем `hl.dsp.submap("reset")`
- **THEN** `qs -c panel ipc call chains state` после первого вызова начинается с «shown ws-sticky:apps», после второго — «shown ws-sticky:apps/raise» с числом строк, равным числу клавиш состояния в `keys --json`, после третьего — «hidden»; слой индикатора в `hyprctl layers` есть только пока карточка показана

#### Scenario: Режим цепочек
- **WHEN** выполнена `hyprctl eval 'hl.dispatch(hl.dsp.submap("ws-sticky:SUPER+TAB"))'`, затем `hl.dsp.submap("reset")`, затем то же для `ws-sticky:SUPER+CTRL+s`
- **THEN** `qs -c panel ipc call chains state` печатает «shown ws-sticky:SUPER+TAB rows=3 …», затем «hidden», затем «shown ws-sticky:SUPER+CTRL+s rows=2 …»; карточка показывает путь «Super+Tab» и «Ctrl+Super+S» и у каждой клавиши пометку «выход»

#### Scenario: Подкарта без префикса индикатора не показывает
- **WHEN** открыта подкарта, имя которой не начинается с `ws-sticky:` (например, `ws:SUPER + TAB` прежних версий)
- **THEN** `qs -c panel ipc call chains state` печатает «hidden»

### Requirement: Содержимое карточки индикатора
В карточке MUST быть путь подписей состояний от корня через « ▸ » («Приложения ▸ Поднять», у режима цепочек — подписи звеньев: «Super+Tab», «Super+W ▸ 3»), клавиши текущего состояния строками «клавиша — описание» с пометкой клавиш выхода и нижняя строка «Backspace — назад · Escape — выход» (в корне — «Backspace — выход · Escape — выход»).

#### Scenario: Состояние «Поднять»
- **WHEN** открыта цепочка `apps` в состоянии «Поднять»
- **THEN** карточка показывает путь «Приложения ▸ Поднять», по строке «клавиша — описание» на каждую клавишу состояния, у клавиши E — пометку выхода, а внизу — «Backspace — назад · Escape — выход»; в корне цепочки нижняя строка — «Backspace — выход · Escape — выход»

#### Scenario: Путь режима цепочек
- **WHEN** нажато Super+Tab
- **THEN** карточка показывает путь «Super+Tab», строки «Tab — Следующий workspace стола», «s — Поднять workspace surf», «w — Поднять workspace work» с пометкой выхода и нижнюю строку «Backspace — выход · Escape — выход»

### Requirement: Состояние индикатора по IPC
Панель MUST объявлять IPC-цель `chains` с функцией `state`: строка «hidden» либо «shown <имя подкарты> rows=<число строк клавиш> card=right-bottom margins=<правый>,<нижний> WxH».

#### Scenario: Индикатор скрыт
- **WHEN** ни цепочка с выходом, ни другая подкарта не открыта
- **THEN** `qs -c panel ipc call chains state` печатает «hidden»

#### Scenario: Положение карточки по IPC
- **WHEN** открыта подкарта `ws-sticky:SUPER+TAB`
- **THEN** `qs -c panel ipc call chains state` печатает строку вида «shown ws-sticky:SUPER+TAB rows=3 card=right-bottom margins=10,10 <ширина>x<высота>»
