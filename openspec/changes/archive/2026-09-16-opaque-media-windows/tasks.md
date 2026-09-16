## 1. Конфиг Hyprland

- [x] 1.1 `dot_config/hypr/hyprland.lua`: правило `opaque-media` для браузеров и видеоплееров без условия `focus` (непрозрачность `1.0 override`, `no_blur`), отдельное правило `opaque-games-focused` для gamescope, `steam_app_*` и `*.exe` с `focus = true`; проверить `luac -p` или `hyprctl reload config-only` без ошибок
- [x] 1.2 `inactive_border = "rgba(2d6a4fee)"`; после `chezmoi apply` и `hyprctl reload config-only` команда `hyprctl getoption general:col.inactive_border` показывает новый цвет

## 2. Проверка вживую (пользователь)

- [x] 2.1 Окно браузера без фокуса рядом с терминалом в фокусе: браузер непрозрачный, без размытия; при переводе фокуса на браузер его вид не меняется
- [x] 2.2 Окно mpv или vlc без фокуса непрозрачное
- [x] 2.3 Рамка окна без фокуса тёмно-зелёная, активного — жёлтая

## 3. Спецификация

- [x] 3.1 `openspec validate opaque-media-windows --strict` проходит, формулировки проверены
