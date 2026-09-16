## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: форма `action = { place = "<позиция>" }` с проверкой восьми позиций; тест: допустимая позиция принимается, `{ place = "left" }` отклоняется с перечнем позиций
- [x] 1.2 `keys.rs`: команда `workspaced place <позиция>` для действия; тест генерации и `keys --list` на тестовом конфиге
- [x] 1.3 `daemon.rs`: функция позиций `place_rect` по правилу отступов (design D4), `half` через ячейку сетки; команда сокета `place`; модульные тесты: при `reserved = [330, 0, 0, 0]`, `gap = 5` все восемь позиций (углы 1740×1065, центры x = 1215, `center` 1215,10 и 1740×2140, `full` = область `maximize`); без зарезервированных зон bottom-left → 10,1085 и 1905×1065; половины дают прежние числа
- [x] 1.4 `main.rs`: подкоманда `place <позиция>`; `cargo test` проходит, `cargo build --release`, `systemctl --user restart workspaced.service` активен

## 2. Конфиг и привязки

- [x] 2.1 `dot_config/workspaced/config.toml`: `[keys]` — `save_workspace = "SUPER+TAB s"`, `next_workspace = "SUPER+TAB Tab"`; цепочки workspace `SUPER+TAB d/w/c`; записи со столом `SUPER+TAB 1 d` и подобные; комментарии обновлены. `workspaced check` без ошибок, `workspaced keys --list` не содержит `SUPER+W`
- [x] 2.2 Половины на `ALT+SUPER+left/right/up/down`; позиции: `ALT+SUPER+Home/Page_Down/End` верхний ряд, `CTRL+ALT+SUPER+Z/X/V` нижний ряд, `CTRL+ALT+SUPER+C` center, `ALT+SUPER+Page_Up` full, `ALT+SUPER+Menu` полноэкранный режим, с комментарием о значении клавиш; `SUPER+SHIFT+стрелки` удалены. `chezmoi apply`, `hyprctl binds` содержит новые сочетания и не содержит старых

## 3. Проверка вживую (нажатия делает пользователь)

- [x] 3.1 Super+Tab d поднимает dots; Super+Tab 2 w переходит на стол 2 и поднимает workspaced; Super+Tab s сохраняет workspace; Super+Tab Tab поднимает следующий workspace стола; Escape закрывает подкарту
- [x] 3.2 Alt+Super+стрелки дают половины с прежними координатами (`hyprctl activewindow -j`)
- [x] 3.3 Позиции: Home/PageDown/End дают 340,10; 1215,10; 2090,10 при 1740×1065, Ctrl+Z/X/V — то же в ряду y = 1085, Ctrl+C — 1215,10 и 1740×2140, PageUp — 340,10 и 3490×2140, Menu — полноэкранный режим и обратно
- [x] 3.4 Super+Shift+стрелки и Super+W ничего не делают

## 4. Спецификации и документация

- [x] 4.1 `openspec validate session-keymap --strict` проходит; в AGENTS.md правило геометрии упоминает `place`, описание привязок — префикс Super+Tab
- [x] 4.2 Проход по формулировкам артефактов, комментариев в коде и конфиге
