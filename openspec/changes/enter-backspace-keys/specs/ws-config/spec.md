## MODIFIED Requirements

### Requirement: Цепочки клавиш и привязки
Цепочка MUST записываться строкой сочетаний через пробел, где сочетание — модификаторы и клавиша в синтаксисе Hyprland через `+` (`"SUPER+W 3 f"`); одиночное сочетание (`"SUPER+Return"`, `"XF86AudioMute"`, `"SUPER+mouse:272"`) — цепочка из одного звена. Короткая форма `chain` у workspace означает действие «поднять на текущем столе», у приложения и у записи приложения в таблице `apps` workspace — клавишу приложения: цикл по его экземплярам по правилам спецификации ws-daemon, «Цепочка приложения». Ключ приложения в workspace — `chain` его записи в этом workspace, а если его нет, собственный `chain` приложения; workspace откликается на цепочку, если в нём есть запись приложения с таким ключом. Переопределение освобождает собственную клавишу приложения в этом workspace: её может занять ключом другое приложение того же workspace. Переопределение, совпадающее с собственной клавишей приложения, ничего не меняет. Все приложения, отзывающиеся на одну цепочку собственной клавишей или ключом в каком-либо workspace, MUST давать одну привязку, вызывающую команду `workspaced key '<цепочка>'`; какое приложение и в каком workspace она вызывает, MUST решать демон при нажатии по активному workspace текущего стола. В `workspaced keys --list` у такой привязки MUST стоять действие `key <цепочка>`, а в колонке источника — все отозвавшиеся записи (`apps.<имя>` для собственной клавиши, `workspaces.<workspace>.apps.<имя>` для ключа в workspace). Запись `[[binds]]` MUST принимать ровно одно действие: `action` — таблица с любым сочетанием ключей `desktop` (1…8), `workspace` и `app` и необязательным логическим ключом `pull` (перетащить окна приложения в активный workspace текущего стола, спецификация ws-daemon, «Цепочка приложения»; ключ допустим только вместе с `app` и без `workspace`, иначе запись MUST отклоняться с указанием цепочки; действие с `pull = true` MUST вызывать команду `workspaced app <имя> --pull`; действие `{ app = "<имя>" }` без `workspace` MUST вызывать команду `workspaced app <имя>`, которая действует как собственная клавиша приложения), таблица `{ half = "left" | "right" | "up" | "down" }`, таблица `{ place = "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right" | "center" | "full" }`, таблица `{ move = <стол 1…8> }` (перенести активный workspace текущего стола на этот стол), таблица `{ fit = "<ширина>x<высота>" }` (окно заданного размера по центру рабочей области, спецификация ws-daemon, «Окно заданного размера по центру»; значение MUST быть двумя положительными целыми через латинскую `x`, иначе запись MUST отклоняться с указанием цепочки и полученного значения; действие MUST вызывать команду `workspaced fit <ширина>x<высота>`, а `workspaced keys --list` MUST показывать его как `fit <ширина>x<высота>`) либо строка `"sessions"`, `"save-session"`, `"save-workspace"`, `"next-workspace"`, `"maximize"`, `"arrange"`, `"detach"` (убрать активное окно из активного workspace текущего стола, спецификация ws-daemon, «Отделение окна»); `exec` — командная строка, запускаемая композитором; `dispatch` — выражение диспетчера Hyprland без префикса `hl.dsp.` (`"window.close()"`) либо массив таких выражений, выполняемых по порядку одним вызовом; `lua` — тело функции на Lua, выполняемое композитором при нажатии. Необязательные строки `desc` (описание) и `group` (группа) записи `[[binds]]` MUST использоваться только перечнем для подсказки (требование «Перечень клавиш для подсказки») и MUST NOT влиять на привязку. Раздел `[keys]` MUST принимать необязательную таблицу `reserved_desc`: сочетание из списка `reserved` → его описание. Флаги `locked` (действует при заблокированном экране), `repeating` (повторяется при удержании), `mouse` (привязка к кнопке мыши с удержанием), `release` (срабатывает при отпускании) MUST передаваться композитору; `mouse` MUST быть допустим только у цепочки из одного звена. Поле `range = [от, до]` MUST разворачивать запись в серию: для каждого целого из диапазона подстрока `$n` в `chain`, `exec`, `dispatch` и в значении действия `move` и в `desc` заменяется числом. Значение `move` MUST читаться числом или строкой и MUST проверяться после разворачивания серии: до него на месте номера стоит `$n`. Стол вне диапазона 1…8 MUST приводить к отказу с указанием цепочки и полученного значения. Цепочки MUST быть произвольными; демон MUST NOT навязывать смысл сегментам. Одна цепочка MUST NOT совпадать с другой или быть её началом, в том числе одиночное сочетание с первым звеном цепочки; две цепочки с общим первым звеном и разными последующими MUST быть допустимы; несколько записей приложений одного workspace с одинаковым ключом MUST быть допустимы, в том числе когда ключ одной из них задан переопределением, а другой — собственной клавишей: такая клавиша ведёт общий цикл по окнам этих приложений (спецификация ws-daemon, «Цепочка приложения»), поэтому режим клавиши (поле `mode` записи, а без него — режим workspace) у таких записей MUST совпадать, иначе конфиг MUST отклоняться; одна цепочка у приложений из разных workspace MUST быть допустима. Цепочка переопределения MUST проходить те же проверки совпадения, начала цепочки и зарезервированных сочетаний, что и остальные цепочки. Сочетание из списка `reserved` раздела `[keys]` MUST NOT встречаться ни в одной цепочке. Демон MUST проверять эти условия при чтении и при ошибке называть обе конфликтующие записи либо запись и зарезервированное сочетание; ошибка разных режимов у записей с общим ключом MUST называть workspace, оба приложения и цепочку.

Многозвенная цепочка MUST задавать режим клавиатуры с выходом на последнем звене (требование «Генерация привязок для Hyprland»): все цепочки с одним первым сочетанием из любых разделов конфига (`[keys]`, `chain` у workspace, у приложения и у записи приложения в workspace, `[[binds]]`) образуют один режим; общее промежуточное звено нескольких цепочек — вложенное состояние режима; последнее звено — клавиша выхода. Сравнение звеньев MUST вестись так же, как сравнение цепочек: модификаторы по порядку, клавиша без учёта регистра. Отдельного признака режима у записи MUST NOT быть: режимом становится каждая цепочка из двух и более звеньев. Звено после первого MUST NOT быть клавишей `Escape` или `BackSpace`, с модификаторами или без: в каждом состоянии режима они возвращают назад и закрывают режим. Два звена одного состояния с одной клавишей, у одного из которых нет модификаторов, MUST отклоняться как неразличимые: звено без модификаторов срабатывает при любых модификаторах. Звенья одной клавиши с разными непустыми наборами модификаторов MUST быть допустимы. Имя подкарты режима, совпадающее с именем подкарты корня цепочки с выходом (требование «Цепочки с выходом»), MUST отклоняться. Ошибки звеньев MUST называть цепочки и их записи.

#### Scenario: Цепочка приложения ведёт цикл
- **WHEN** у приложения `chromium` задано `chain = "SUPER+C"`, оно входит в workspace `work` режима обмена ячеек, и у него два окна
- **THEN** Super+C по очереди выбирает экземпляры `chromium` в главной ячейке, а за последним возвращает расстановку и фокус прежнему главному окну

#### Scenario: Отделение окна в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+SHIFT+Delete"` и `action = "detach"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Shift+Super+Delete команду `detach`, а запись с `action = "detahc"` отклоняется как неизвестное действие

#### Scenario: Одна цепочка у двух приложений в разных workspace
- **WHEN** `firefox-front` и `firefox-chat` имеют `chain = "SUPER+A b"`, первое входит в `dev-front`, второе в `chat`
- **THEN** `workspaced check` завершается успешно

#### Scenario: Одна цепочка у двух приложений одного workspace
- **WHEN** `firefox-front` и `firefox-back` имеют `chain = "SUPER+A b"` и оба входят в `dev-front`
- **THEN** `workspaced check` завершается с ошибкой, называющей `dev-front` и оба приложения

#### Scenario: Переопределение клавиши в workspace
- **WHEN** у `chrome-ai` задано `chain = "SUPER+SHIFT+V"`, а в разделе `surf` — `chrome-ai = { cell = "right", chain = "SUPER+V" }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для `SUPER+V` действие `key SUPER+V` с источником `workspaces.surf.apps.chrome-ai`, для `SUPER+SHIFT+V` — действие `key SUPER+SHIFT+V` с источником `apps.chrome-ai`

#### Scenario: Переопределение освобождает собственную клавишу
- **WHEN** у `chrome` задано `chain = "SUPER+B"`, у `chrome-ai` — `chain = "SUPER+V"`, а в разделе `surf` записаны `chrome = { cell = "left", chain = "SUPER+V" }` и `chrome-ai = { cell = "right", chain = "SUPER+B" }`
- **THEN** `workspaced check` завершается успешно: ключи в `surf` различаются

#### Scenario: Переопределение совпадает с клавишей другого приложения workspace
- **WHEN** у `chrome` задано `chain = "SUPER+B"`, в разделе `surf` записаны `chrome = "left"` и `chrome-ai = { cell = "right", chain = "SUPER+B" }`
- **THEN** `workspaced check` завершается успешно, а `workspaced keys --list` показывает одну привязку Super+B с источниками `apps.chrome,workspaces.surf.apps.chrome-ai`: в `surf` она ведёт общий цикл по окнам `chrome` и `chrome-ai`

#### Scenario: Две записи workspace с общим ключом
- **WHEN** в разделе `surf` записаны `chrome-ai = { cell = "right", chain = "SUPER+V" }` и `chrome-ai2 = { cell = "right", chain = "SUPER+V" }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает одну привязку Super+V с действием `key SUPER+V` и источниками `workspaces.surf.apps.chrome-ai,workspaces.surf.apps.chrome-ai2`, а цепочка с выходом `[sticky.apps]` наследует букву V один раз

#### Scenario: Разные режимы у записей с общим ключом
- **WHEN** в разделе `surf` (режим `stack`) записаны `chrome-ai = { cell = "right", chain = "SUPER+V" }` и `chrome-ai2 = { cell = "right", chain = "SUPER+V", mode = "swap" }`
- **THEN** `workspaced check` завершается с ошибкой, называющей `surf`, `chrome-ai`, `chrome-ai2` и цепочку `SUPER+V`

#### Scenario: Переопределение совпадает с цепочкой workspace
- **WHEN** у `surf` задано `chain = "SUPER+TAB s"`, а в его разделе записано `chrome-ai = { cell = "right", chain = "SUPER+TAB s" }`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе записи

#### Scenario: Общий префикс у двух цепочек
- **WHEN** в `[keys]` заданы `save_session = "CTRL+SUPER+s CTRL+SUPER+s"` и `save_workspace = "CTRL+SUPER+s CTRL+SUPER+w"`
- **THEN** `workspaced check` завершается успешно, а `hyprctl binds` содержит одну подкарту режима `ws-sticky:SUPER+CTRL+s`, открываемую Ctrl+Super+S, с двумя действиями внутри

#### Scenario: Цепочки разных разделов в одном режиме
- **WHEN** в `[keys]` задано `next_workspace = "SUPER+TAB Tab"`, у workspace `work` — `chain = "SUPER+TAB w"`, у `surf` — `chain = "SUPER+TAB s"`
- **THEN** `workspaced check` завершается успешно и печатает строку режима `SUPER+TAB` с источниками `keys.next_workspace`, `workspaces.surf`, `workspaces.work`; `hyprctl binds` содержит одну подкарту `ws-sticky:SUPER+TAB` с клавишами `Tab`, `s` и `w`

#### Scenario: Escape звеном цепочки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+X Escape"` либо `chain = "SUPER+X SUPER+Escape"`
- **THEN** `workspaced check` завершается с ошибкой, называющей цепочку, запись `binds[N]` и занятость Escape и BackSpace

#### Scenario: Неразличимые звенья
- **WHEN** в `[[binds]]` есть `chain = "SUPER+X w"` и `chain = "SUPER+X SUPER+w"`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе цепочки; с `chain = "SUPER+X SUPER+w"` и `chain = "SUPER+X CTRL+w"` проверка проходит

#### Scenario: Цепочка является началом другой
- **WHEN** у workspace `chain = "SUPER+W f"`, а в `[[binds]]` есть `chain = "SUPER+W f 3"`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе цепочки

#### Scenario: Одиночное сочетание совпадает с началом цепочки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+W"` с `exec = "wezterm-gui"`, а у workspace `chain = "SUPER+W d"`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе записи

#### Scenario: Запуск команды с флагами
- **WHEN** в `[[binds]]` есть `chain = "XF86AudioRaiseVolume"`, `exec = "~/.local/bin/handmade-scripts/change-volume.sh +"`, `locked = true`, `repeating = true`
- **THEN** после `hyprctl reload` удержание клавиши повышает громкость несколько раз подряд, в том числе при экране, закрытом hyprlock

#### Scenario: Серия по диапазону
- **WHEN** в `[[binds]]` есть `chain = "SUPER+$n"`, `range = [1, 8]`, `dispatch = "focus({ workspace = $n })"`
- **THEN** `hyprctl binds` содержит восемь привязок Super+1…Super+8, и Super+3 переводит на стол «3»

#### Scenario: Несколько диспетчеров по порядку
- **WHEN** в `[[binds]]` есть `chain = "ALT+Tab"` и `dispatch = ["window.cycle_next({ next = true })", "window.bring_to_top()"]`
- **THEN** нажатие Alt+Tab переводит фокус на следующее окно стола, и оно оказывается поверх остальных

#### Scenario: Зарезервированное сочетание
- **WHEN** в `[keys]` задано `reserved = ["SUPER+space", "ALT+SUPER+E"]`, а в `[[binds]]` есть `chain = "ALT+SUPER+E"`
- **THEN** `workspaced check` завершается с ошибкой, называющей запись и зарезервированное сочетание

#### Scenario: Развёртывание окна в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+X"` и `action = "maximize"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Super+X команду `workspaced maximize`, а запись с `action = "maximise"` отклоняется как неизвестное действие

#### Scenario: Окно заданного размера в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+Return"` и `action = { fit = "1920x1080" }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для `SUPER+Return` действие `fit 1920x1080`, а `workspaced keys --lua` — привязку, вызывающую `workspaced fit 1920x1080`

#### Scenario: Неверный размер в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+Return"` и `action = { fit = "1920" }`, либо `fit = "0x1080"`, либо `fit = "1920x-5"`, либо `fit = "1920×1080"` со знаком умножения
- **THEN** `workspaced check` завершается с ошибкой, называющей цепочку `SUPER+Return` и полученное значение, демон продолжает работать с прежним конфигом

#### Scenario: Позиция в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "ALT+SUPER+Home"` и `action = { place = "top-left" }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает команду `workspaced place top-left`, а запись с `action = { place = "left" }` отклоняется с перечнем допустимых позиций

#### Scenario: Перенос workspace на стол в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "CTRL+SUPER+$n"`, `range = [1, 8]` и `action = { move = "$n" }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Ctrl+Super+3 команду `move-desktop 3`, а запись с `move = 9` отклоняется с указанием цепочки и значения

#### Scenario: Расстановка окон в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "CTRL+SUPER+space"` и `action = "arrange"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Ctrl+Super+Пробел команду `arrange`, а запись с `action = "arange"` отклоняется как неизвестное действие

#### Scenario: Мышь в цепочке
- **WHEN** в `[[binds]]` есть `chain = "SUPER+W mouse:272"` с `mouse = true`
- **THEN** `workspaced check` завершается с ошибкой о том, что флаг `mouse` допустим только у одиночного сочетания

#### Scenario: Перетаскивание в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+TAB v"` и `action = { app = "chrome-ai", pull = true }`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для `SUPER+TAB v` команду `app chrome-ai --pull`, а запись с `action = { workspace = "surf", pull = true }` отклоняется с указанием цепочки и ключа `pull`

#### Scenario: Описание и группа записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+SHIFT+slash"`, `exec = "qs -c panel ipc call keys toggle"`, `desc = "Подсказка клавиш"` и `group = "Справка"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --lua` печатает ту же привязку, что и без полей `desc` и `group`, а `workspaced keys --json` показывает строку «Shift+Super+/ — Подсказка клавиш» в группе «Справка»
