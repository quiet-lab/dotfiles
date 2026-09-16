## 1. Удаление спецификаций eww

- [x] 1.1 Удалить каталоги `openspec/specs/eww-*` (девять) через `git rm -r`; `openspec list --specs` (или `ls openspec/specs`) больше не показывает `eww-*`, `openspec validate --all` проходит

## 2. Разделы Purpose

- [x] 2.1 Переписать Purpose в hyprland-autostart, hyprland-config, hyprland-session, hyprland-binds, qs-clock-calendar, qs-launcher, qs-monitors, qs-shell, qs-tray-lang, qs-weather без слов Openbox, eww, picom и «переезд»; проверить `rg -i 'openbox|eww|picom' openspec/specs` — совпадений нет вне архива после архивирования этого изменения

## 3. Документация

- [x] 3.1 В AGENTS.md фраза о спецификациях `eww-*` заменена на указание, что история Openbox и eww хранится только в `openspec/changes/archive`
- [x] 3.2 `openspec validate drop-openbox-specs --strict` проходит; проход по формулировкам новых требований
