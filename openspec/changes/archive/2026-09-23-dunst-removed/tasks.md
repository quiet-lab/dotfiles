## 1. Система (сделано 23.09.2026)

- [x] 1.1 Скрипты `dot_local/bin/handmade-scripts/` переведены с `dunstify`
      на `notify-send` с подсказкой `string:synchronous:<метка>`
      (коммит `8dd47b5`)
- [x] 1.2 Пакет `dunst` удалён из системы (`pacman -Q dunst` не находит
      пакет)
- [x] 1.3 Маска юнита `dot_config/systemd/user/symlink_dunst.service` убрана
      из источника chezmoi и из `$HOME`; юнита `dunst.service` в системе нет
      (`systemctl --user status dunst.service` → «could not be found»)

## 2. Спецификации (это изменение)

- [x] 2.1 `openspec/specs/qs-notifications/spec.md`: требование «Сервер
      уведомлений сессии» приведено к состоянию без маски юнита
- [x] 2.2 `openspec/specs/hyprland-autostart/spec.md`: требование «Состав
      автозапуска» приведено к тому же состоянию
- [x] 2.3 `openspec validate dunst-removed --strict` проходит
- [x] 2.4 `openspec archive dunst-removed -y`, `openspec validate --specs`
      проходит
