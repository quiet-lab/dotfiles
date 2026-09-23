## MODIFIED Requirements

### Requirement: Цепочки клавиш и привязки
Цепочка MUST записываться строкой сочетаний через пробел, где сочетание — модификаторы и клавиша в синтаксисе Hyprland через `+` (`"SUPER+W 3 f"`); одиночное сочетание (`"SUPER+Return"`, `"XF86AudioMute"`, `"SUPER+mouse:272"`) — цепочка из одного звена. Короткая форма `chain` у workspace означает действие «поднять на текущем столе», у приложения и у записи приложения в таблице `apps` workspace — клавишу приложения: цикл по его экземплярам по правилам спецификации ws-daemon, «Цепочка приложения». Ключ приложения в workspace — `chain` его записи в этом workspace, а если его нет, собственный `chain` приложения; workspace откликается на цепочку, если в нём есть запись приложения с таким ключом. Переопределение освобождает собственную клавишу приложения в этом workspace: её может занять ключом другое приложение того же workspace. Переопределение, совпадающее с собственной клавишей приложения, ничего не меняет. Все приложения, отзывающиеся на одну цепочку собственной клавишей или ключом в каком-либо workspace, MUST давать одну привязку, вызывающую команду `workspaced key '<цепочка>'`; какое приложение и в каком workspace она вызывает, MUST решать демон при нажатии по активному workspace текущего стола. В `workspaced keys --list` у такой привязки MUST стоять действие `key <цепочка>`, а в колонке источника — все отозвавшиеся записи (`apps.<имя>` для собственной клавиши, `workspaces.<workspace>.apps.<имя>` для ключа в workspace). Запись `[[binds]]` MUST принимать ровно одно действие: `action` — таблица с любым сочетанием ключей `desktop` (1…8), `workspace` и `app` и необязательным логическим ключом `pull` (перетащить окна приложения в активный workspace текущего стола, спецификация ws-daemon, «Цепочка приложения»; ключ допустим только вместе с `app` и без `workspace`, иначе запись MUST отклоняться с указанием цепочки; действие с `pull = true` MUST вызывать команду `workspaced app <имя> --pull`; действие `{ app = "<имя>" }` без `workspace` MUST вызывать команду `workspaced app <имя>`, которая действует как собственная клавиша приложения), таблица `{ half = "left" | "right" | "up" | "down" }`, таблица `{ place = "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right" | "center" | "full" }`, таблица `{ move = <стол 1…8> }` (перенести активный workspace текущего стола на этот стол) либо строка `"sessions"`, `"save-session"`, `"save-workspace"`, `"next-workspace"`, `"maximize"`, `"arrange"`, `"detach"` (убрать активное окно из активного workspace текущего стола, спецификация ws-daemon, «Отделение окна»); `exec` — командная строка, запускаемая композитором; `dispatch` — выражение диспетчера Hyprland без префикса `hl.dsp.` (`"window.close()"`) либо массив таких выражений, выполняемых по порядку одним вызовом; `lua` — тело функции на Lua, выполняемое композитором при нажатии. Необязательные строки `desc` (описание) и `group` (группа) записи `[[binds]]` MUST использоваться только перечнем для подсказки (требование «Перечень клавиш для подсказки») и MUST NOT влиять на привязку. Раздел `[keys]` MUST принимать необязательную таблицу `reserved_desc`: сочетание из списка `reserved` → его описание. Флаги `locked` (действует при заблокированном экране), `repeating` (повторяется при удержании), `mouse` (привязка к кнопке мыши с удержанием), `release` (срабатывает при отпускании) MUST передаваться композитору; `mouse` MUST быть допустим только у цепочки из одного звена. Поле `range = [от, до]` MUST разворачивать запись в серию: для каждого целого из диапазона подстрока `$n` в `chain`, `exec`, `dispatch` и в значении действия `move` и в `desc` заменяется числом. Значение `move` MUST читаться числом или строкой и MUST проверяться после разворачивания серии: до него на месте номера стоит `$n`. Стол вне диапазона 1…8 MUST приводить к отказу с указанием цепочки и полученного значения. Цепочки MUST быть произвольными; демон MUST NOT навязывать смысл сегментам. Одна цепочка MUST NOT совпадать с другой или быть её началом, в том числе одиночное сочетание с первым звеном цепочки; две цепочки с общим первым звеном и разными последующими MUST быть допустимы; две записи приложений одного workspace с одинаковым ключом MUST считаться ошибкой, в том числе когда ключ одной из них задан переопределением, а другой — собственной клавишей; одна цепочка у приложений из разных workspace MUST быть допустима. Цепочка переопределения MUST проходить те же проверки совпадения, начала цепочки и зарезервированных сочетаний, что и остальные цепочки. Сочетание из списка `reserved` раздела `[keys]` MUST NOT встречаться ни в одной цепочке. Демон MUST проверять эти условия при чтении и при ошибке называть обе конфликтующие записи либо запись и зарезервированное сочетание; ошибка двух записей одного workspace MUST называть workspace, оба приложения и цепочку.

#### Scenario: Цепочка приложения ведёт цикл
- **WHEN** у приложения `chromium` задано `chain = "SUPER+C"`, оно входит в workspace `work` режима обмена ячеек, и у него два окна
- **THEN** Super+C по очереди выбирает экземпляры `chromium` в главной ячейке, а за последним возвращает расстановку и фокус прежнему главному окну

#### Scenario: Отделение окна в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+BackSpace"` и `action = "detach"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Super+Backspace команду `detach`, а запись с `action = "detahc"` отклоняется как неизвестное действие

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
- **THEN** `workspaced check` завершается с ошибкой, называющей `surf`, `chrome`, `chrome-ai` и цепочку `SUPER+B`

#### Scenario: Переопределение совпадает с цепочкой workspace
- **WHEN** у `surf` задано `chain = "SUPER+TAB s"`, а в его разделе записано `chrome-ai = { cell = "right", chain = "SUPER+TAB s" }`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе записи

#### Scenario: Общий префикс у двух цепочек
- **WHEN** в `[keys]` заданы `save_session = "CTRL+SUPER+s CTRL+SUPER+s"` и `save_workspace = "CTRL+SUPER+s CTRL+SUPER+w"`
- **THEN** `workspaced check` завершается успешно, а `hyprctl binds` содержит одну подкарту, открываемую Ctrl+Super+S, с двумя действиями внутри

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

## ADDED Requirements

### Requirement: Перечень клавиш для подсказки
Команда `workspaced keys --json` MUST печатать перечень всех привязок конфига в JSON вида `{ "groups": [ { "name": <группа>, "keys": [ { "chain", "label", "desc", "action", "source" } ] } ] }`. `chain` и `action` MUST совпадать с цепочкой и действием в выводе `keys --list`, `source` — раздел конфига (`keys.next_workspace`, `apps.herdr`, `workspaces.surf.apps.chrome`, `workspaces.work`, `binds[N]`, `keys.reserved`). `label` MUST быть подписью для человека: модификаторы в порядке Ctrl, Alt, Shift, Super, звенья через пробел, `slash` — «/», `space` — «Пробел», `Return` — «Enter», стрелки — символами, кнопки мыши — «ЛКМ» и «ПКМ», без префикса `XF86`; буква с модификаторами заглавная. Команда MUST читать конфиг сама и MUST NOT требовать работающего демона. При ошибке конфига команда MUST завершаться ненулевым кодом с описанием ошибки в stderr и MUST NOT печатать частичный перечень.

Группы MUST идти в порядке: Workspace, Столы, Приложения, Окна, Уведомления, Звук и яркость, Снимки экрана, Раскладка, Сессия и прочее; группа из поля `group`, которой нет в этом списке, MUST идти после них в порядке первого появления; пустая группа MUST NOT выводиться. Строки внутри группы MUST идти в порядке `keys --list`, зарезервированные сочетания — последними в группе «Раскладка». Запись `[[binds]]` с `range` MUST выводиться одной строкой, где `$n` в цепочке, описании и действии заменено подписью «от…до» («Super+1…8»). Каждое сочетание списка `reserved` MUST выводиться в группе «Раскладка» с описанием из `reserved_desc`, а без него — «Зарезервировано».

Без поля `group` группа MUST выводиться из источника и действия: цепочки workspace и служебные цепочки `[keys]`, действия `next-workspace`, `save-session`, `save-workspace`, `sessions`, `arrange` и `{ workspace = … }` — Workspace; `{ move = … }` и `dispatch` с переходом или переносом окна на стол (`workspace = ` без `special:`) — Столы; клавиши приложений и `{ app = … }` — Приложения; `half`, `place`, `maximize`, `detach` и прочие `dispatch` — Окна; `exec` с `ipc call notifications` — Уведомления; `exec` громкости, яркости и `playerctl`, цепочки `XF86Audio*` и `XF86MonBrightness*` — Звук и яркость; `exec` со `screenshot` — Снимки экрана; `dispatch` с `exit()`, прочие `exec` и `lua` — Сессия и прочее. Без поля `desc` описание MUST выводиться из действия: у действий демона — фразой по-русски («Окно в левую половину»), у клавиш приложений — по источнику («Приложение herdr», «chrome в workspace surf»), у цепочек workspace — «Поднять workspace <имя>», у `exec`, `dispatch` и `lua` — действием, как в `keys --list`.

#### Scenario: Группы и подписи
- **WHEN** выполнена `workspaced keys --json` с конфигом сессии
- **THEN** первая группа — «Workspace» со строкой `label` «Super+Tab w» и описанием «Поднять workspace work», в группе «Приложения» есть строка «Super+B — chrome в workspace surf», в группе «Окна» — «Alt+Super+← — Окно в левую половину»

#### Scenario: Серия одной строкой
- **WHEN** в `[[binds]]` есть `chain = "CTRL+SUPER+$n"`, `range = [1, 8]`, `action = { move = "$n" }` без `desc`
- **THEN** в группе «Столы» ровно одна строка этой записи: «Ctrl+Super+1…8 — Перенести workspace на стол 1…8 и перейти туда»

#### Scenario: Зарезервированные сочетания
- **WHEN** в `[keys]` заданы `reserved = ["SUPER+space", "ALT+SUPER+space"]` и `reserved_desc = { "SUPER+space" = "Следующая раскладка" }`
- **THEN** в группе «Раскладка» есть строки «Super+Пробел — Следующая раскладка» и «Alt+Super+Пробел — Зарезервировано»

#### Scenario: Ошибка конфига
- **WHEN** привязка занимает зарезервированное сочетание и выполнена `workspaced keys --json`
- **THEN** команда завершается ненулевым кодом, в stderr названы запись и сочетание, stdout пуст
