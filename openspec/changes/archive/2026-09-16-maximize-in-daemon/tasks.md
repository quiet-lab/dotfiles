## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: добавить `"maximize"` в перечень допустимых служебных действий проверки; проверить тестом, что `action = "maximize"` принимается, а `action = "maximise"` отклоняется с указанием привязки
- [x] 1.2 `keys.rs`: для `Action::Named("maximize")` печатать команду `workspaced maximize`; проверить тестом генерации и командой `workspaced keys --list` на тестовом конфиге
- [x] 1.3 `hypr.rs`: добавить в `Client` поле `fullscreen` (число, по умолчанию 0) и вспомогательную функцию для получения списка клиентов, если её нет; проверить `cargo build`
- [x] 1.4 `daemon.rs`: реализовать `maximize` по design D2–D6 (память `HashMap<String, PxRect>`, очистка по списку клиентов, сравнение с целевым прямоугольником, пропуск полноэкранного окна, `mark_dirty`); команда сокета `maximize`; модульный тест расчёта целевого прямоугольника для монитора 3840×2160 с `reserved = [330, 0, 0, 0]` и `gap = 5` → 340,10 и 3490×2140, и без зарезервированных зон → 10,10 и 3820×2140
- [x] 1.5 `main.rs`: подкоманда `maximize`; проверить `workspaced maximize --help` и `cargo test` (все тесты проходят)
- [x] 1.6 Собрать `cargo build --release`, убедиться, что `~/.local/bin/workspaced` указывает на новую сборку (`workspaced --version` или дата файла), перезапустить `systemctl --user restart workspaced.service` и проверить `systemctl --user is-active workspaced.service`

## 2. Конфиг и привязка

- [x] 2.1 `dot_config/workspaced/config.toml`: заменить запись Super+X на `action = "maximize"` с комментарием про правило отступов; `chezmoi apply ~/.config/workspaced/config.toml`, `workspaced check` без ошибок, `workspaced keys --list` показывает для Super+X команду `workspaced maximize`, `hyprctl binds` содержит Super+X

## 3. Проверка вживую (нажатия делает пользователь)

- [x] 3.1 Развёртывание при панели слева: окно после `half left` (340,10, 1740×2140) → Super+X → `hyprctl activewindow -j` показывает 340,10 и 3490×2140; повторное Super+X возвращает 340,10 и 1740×2140
- [x] 3.2 Сдвинутое окно: после развёртывания передвинуть окно мышью, Super+X разворачивает заново, следующее Super+X возвращает сдвинутое положение
- [x] 3.3 Пустой стол: Super+X ничего не меняет, в `journalctl --user -u workspaced` запись без ошибки; полноэкранное окно (Super+F): Super+X выводит его из полноэкранного режима и разворачивает с отступами, следующее Super+X возвращает прежнюю геометрию
- [x] 3.4 Перезапуск демона при развёрнутом окне: Super+X не меняет окно, в журнале запись о неизвестной прежней геометрии

## 4. Спецификации и документация

- [x] 4.1 `openspec validate maximize-in-daemon --strict` проходит; в AGENTS.md в разделе о сессии Hyprland упомянуть команду `workspaced maximize` рядом с `half`
- [x] 4.2 Проход по формулировкам proposal, design, спецификаций и комментариев в коде демона и конфиге: русский язык без калек и разговорных оборотов
- [x] 4.3 `hyprland.lua`: `border_size = 1`, `chezmoi apply`, `hyprctl reload config-only`, `hyprctl getoption general:border_size` показывает 1
