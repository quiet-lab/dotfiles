## MODIFIED Requirements

### Requirement: Цепочки клавиш и привязки
Цепочка MUST записываться строкой сочетаний через пробел, где сочетание — модификаторы и клавиша в синтаксисе Hyprland через `+` (`"SUPER+W 3 f"`); одиночное сочетание (`"SUPER+Return"`, `"XF86AudioMute"`, `"SUPER+mouse:272"`) — цепочка из одного звена. Короткая форма `chain` у workspace означает действие «поднять на текущем столе», у приложения — «сделать главным» по правилам ws-daemon. Запись `[[binds]]` MUST принимать ровно одно действие: `action` — таблица с любым сочетанием ключей `desktop` (1…8), `workspace` и `app`, таблица `{ half = "left" | "right" | "up" | "down" }` либо строка `"sessions"`, `"save-workspace"`, `"next-workspace"`, `"maximize"`; `exec` — командная строка, запускаемая композитором; `dispatch` — выражение диспетчера Hyprland без префикса `hl.dsp.` (`"window.close()"`) либо массив таких выражений, выполняемых по порядку одним вызовом; `lua` — тело функции на Lua, выполняемое композитором при нажатии. Флаги `locked` (действует при заблокированном экране), `repeating` (повторяется при удержании), `mouse` (привязка к кнопке мыши с удержанием), `release` (срабатывает при отпускании) MUST передаваться композитору; `mouse` MUST быть допустим только у цепочки из одного звена. Поле `range = [от, до]` MUST разворачивать запись в серию: для каждого целого из диапазона подстрока `$n` в `chain`, `exec` и `dispatch` заменяется числом. Цепочки MUST быть произвольными; демон MUST NOT навязывать смысл сегментам. Одна цепочка MUST NOT совпадать с другой или быть её началом, в том числе одиночное сочетание с первым звеном цепочки; два приложения с одной цепочкой внутри одного workspace MUST считаться ошибкой; одна цепочка у приложений из разных workspace MUST быть допустима. Сочетание из списка `reserved` раздела `[keys]` MUST NOT встречаться ни в одной цепочке. Демон MUST проверять эти условия при чтении и при ошибке называть обе конфликтующие записи либо запись и зарезервированное сочетание.

#### Scenario: Одна цепочка у двух приложений в разных workspace
- **WHEN** `firefox-front` и `firefox-chat` имеют `chain = "SUPER+A b"`, первое входит в `dev-front`, второе в `chat`
- **THEN** `workspaced check` завершается успешно

#### Scenario: Одна цепочка у двух приложений одного workspace
- **WHEN** `firefox-front` и `firefox-back` имеют `chain = "SUPER+A b"` и оба входят в `dev-front`
- **THEN** `workspaced check` завершается с ошибкой, называющей `dev-front` и оба приложения

#### Scenario: Цепочка является началом другой
- **WHEN** у workspace `chain = "SUPER+W f"`, а в `[[binds]]` есть `chain = "SUPER+W f 3"`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе цепочки

#### Scenario: Одиночное сочетание совпадает с началом цепочки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+W"` с `exec = "wezterm-gui"`, а у workspace `chain = "SUPER+W d"`
- **THEN** `workspaced check` завершается с ошибкой, называющей обе записи

#### Scenario: Запуск команды с флагами
- **WHEN** в `[[binds]]` есть `chain = "XF86AudioRaiseVolume"`, `exec = "~/.scripts/change-volume.sh +"`, `locked = true`, `repeating = true`
- **THEN** после `hyprctl reload` удержание клавиши повышает громкость несколько раз подряд, в том числе при экране, закрытом hyprlock

#### Scenario: Серия по диапазону
- **WHEN** в `[[binds]]` есть `chain = "SUPER+$n"`, `range = [1, 8]`, `dispatch = "focus({ workspace = $n })"`
- **THEN** `hyprctl binds` содержит восемь привязок Super+1…Super+8, и Super+3 переводит на стол «3»

#### Scenario: Несколько диспетчеров по порядку
- **WHEN** в `[[binds]]` есть `chain = "ALT+Tab"` и `dispatch = ["window.cycle_next({ next = true })", "window.bring_to_top()"]`
- **THEN** нажатие Alt+Tab переводит фокус на следующее окно стола, и оно оказывается поверх остальных

#### Scenario: Зарезервированное сочетание
- **WHEN** в `[keys]` задано `reserved = ["SUPER+space", "ALT+E"]`, а в `[[binds]]` есть `chain = "ALT+E"`
- **THEN** `workspaced check` завершается с ошибкой, называющей запись и зарезервированное сочетание

#### Scenario: Развёртывание окна в записи привязки
- **WHEN** в `[[binds]]` есть `chain = "SUPER+X"` и `action = "maximize"`
- **THEN** `workspaced check` завершается успешно, `workspaced keys --list` показывает для Super+X команду `workspaced maximize`, а запись с `action = "maximise"` отклоняется как неизвестное действие

#### Scenario: Мышь в цепочке
- **WHEN** в `[[binds]]` есть `chain = "SUPER+W mouse:272"` с `mouse = true`
- **THEN** `workspaced check` завершается с ошибкой о том, что флаг `mouse` допустим только у одиночного сочетания
