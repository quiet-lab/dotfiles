## ADDED Requirements

### Requirement: Раздел сторожа внимания
Необязательный раздел `[attention]` MUST задавать сторож внимания (спецификация ws-attention) полями `enabled` (по умолчанию `false`, без раздела сторож выключен), `app` (приложение из `[apps]`, окно которого получает фокус; по умолчанию `herdr`), `media_pause` и `freeze_fullscreen` (по умолчанию `true`) и `freeze_exclude_classes` (выражения по классу окна целиком, как `ignore_classes`). Раздел MUST перечитываться вместе с конфигом.

#### Scenario: Раздел сторожа
- **WHEN** в конфиге `[attention]` с `enabled = true` и `freeze_exclude_classes = ["(?i)google-chrome.*", "wezterm.*"]`, а приложение `herdr` описано
- **THEN** `workspaced check` завершается успешно

### Requirement: Проверка раздела сторожа
Неизвестный ключ раздела `[attention]`, выражение с ошибкой в `freeze_exclude_classes` и включённый раздел с `app`, которого нет в `[apps]`, MUST приводить к отказу с указанием `attention` и поля.

#### Scenario: Ошибка в разделе сторожа
- **WHEN** в `[attention]` записано `app = "nope"` при `enabled = true` или выражение `"(["` в `freeze_exclude_classes`
- **THEN** конфиг отклоняется с указанием `attention`
