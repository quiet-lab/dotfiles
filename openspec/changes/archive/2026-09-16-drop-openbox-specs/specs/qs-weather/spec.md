## MODIFIED Requirements

### Requirement: Источник данных
Данные погоды MUST поставлять скрипт `dot_config/quickshell/panel/scripts/weather` (в `$HOME` — `~/.config/quickshell/panel/scripts/weather`), запрашивающий `https://wttr.in/<CITY>?format=j1` командой `curl -sf --max-time 10`. Пустая переменная `CITY` в скрипте MUST означать автоопределение города по IP-адресу; непустая — запрос к `wttr.in/<CITY>`. Название города MUST браться из ответа wttr.in (поле `nearest_area`), а не из переменной. Панель MUST запускать скрипт при старте и далее раз в 30 минут.

#### Scenario: Указанный город
- **WHEN** в скрипте задано `CITY="Minsk"`
- **THEN** запрос идёт к `wttr.in/Minsk`, а в сводке показано название города из ответа wttr.in

#### Scenario: Периодическое обновление
- **WHEN** панель работает без перезапуска дольше 30 минут
- **THEN** скрипт погоды выполнен повторно, и сводка отражает свежий ответ wttr.in
