## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `config.rs`: действие `{ fit = "<ширина>x<высота>" }` в `[[binds]]`, разбор и проверка значения (положительные целые, латинская `x`), отказ с цепочкой и значением. Проверка: модульный тест на `1920x1080` и отказы `1920`, `0x1080`, `1920x-5`, `1920×1080`.
- [x] 1.2 `main.rs`, `client.rs`: команда `workspaced fit <ширина>x<высота>` с той же проверкой аргумента. Проверка: `workspaced fit 1920` завершается ошибкой, называющей значение.
- [x] 1.3 `daemon.rs`: обработчик `fit` (плавающий режим, размер, центр рабочей области по `work_area`, переключатель, вывод из fullscreen и maximized композитора) и общая с `maximize` запомненная геометрия с прямоугольником, куда окно поставила последняя команда (`design.md`, D1, D2). Проверка: модульные тесты расчёта прямоугольника (1125,540 при зоне 330 px) и шагов переключателя: цепочки «`maximize` → `fit` → `fit`» и «`fit` → `maximize` → `maximize`» возвращают исходное, ручной сдвиг перезаписывает.
- [x] 1.4 `keys.rs`, `keys_help.rs`: привязка `workspaced fit 1920x1080`, действие `fit 1920x1080` в `keys --list`, описание по умолчанию и группа «Окна». Проверка: модульные тесты `keys --list`, `keys --lua`, `keys --json`.
- [x] 1.5 Сборка и проверки: `cargo test`, `cargo clippy`, `cargo build --release`, ревью diff. Проверка: тесты и clippy без замечаний.

## 2. Конфиг

- [x] 2.1 `dot_config/workspaced/config.toml`: `SUPER+SHIFT+Delete` — `detach`, `SUPER+BackSpace` — `invokeOldest`, `SUPER+SHIFT+BackSpace` — `clear`, `SUPER+Return` — `{ fit = "1920x1080" }`, `SUPER+SHIFT+Return` — `maximize`; удалены `SUPER+CTRL+Return`, `SUPER+CTRL+ALT+Return`, `ALT+SUPER+Return` и прежние записи этих сочетаний; `desc`, `group` и комментарии (`design.md`, D4). Проверка: `workspaced check` без ошибок, `chezmoi apply`.

## 3. Документы

- [x] 3.1 `AGENTS.md` (он же `CLAUDE.md`): Super+Backspace → Shift+Super+Delete, клавиши уведомлений, Alt+Super+Enter → Super+Enter с возвратом, Shift+Super+Enter. Проверка: `rg -n 'Alt\+Super\+Enter|Super\+Ctrl\+Enter|Super\+Ctrl\+Alt\+Enter' AGENTS.md` пуст.
- [x] 3.2 `docs/window-model.md`: упоминания Super+Backspace как отделения окна заменены на Shift+Super+Delete, запись об изменении в разделе изменённых требований. Проверка: `rg -n 'Super\+Backspace' docs/window-model.md` находит только исторические записи изменений.

## 4. Проверка автоматическая (агент)

- [x] 4.1 `workspaced check` и `workspaced keys --list`. Проверка: `SUPER+Return` — `fit 1920x1080`, `SUPER+SHIFT+Return` и `ALT+SUPER+Page_Up` — `maximize`, `SUPER+SHIFT+Delete` — `detach`, `SUPER+BackSpace` и `SUPER+SHIFT+BackSpace` — вызовы `notifications invokeOldest` и `clear`; сочетаний `SUPER+CTRL+Return`, `SUPER+CTRL+ALT+Return`, `ALT+SUPER+Return` нет.
- [x] 4.2 `hyprctl binds -j` после перечитывания конфига демоном. Проверка: те же сочетания с теми же командами, других привязок с клавишей `Return` нет.
- [x] 4.3 `workspaced fit 1920x1080` и `workspaced maximize` на активном окне с замером `hyprctl activewindow -j`. Проверка: окно 400,300 → `fit` 1125,540 1920×1080 → `fit` 400,300; `maximize` 340,10 3490×2140 → `fit` 1125,540 → `fit` исходное; `fit` → `maximize` → `maximize` исходное.
- [x] 4.4 Вызовы IPC панели `invokeOldest` и `clear` не менялись; привязки к ним проверены по `hyprctl binds -j` (пункт 4.2). Вызов `clear` агентом не выполнялся: он удалил бы историю уведомлений пользователя; действие клавиш проверяет пользователь (пункты 5.4 и 5.5).

## 5. Проверка вживую (пользователь)

- [ ] 5.1 Super+Enter дважды на плавающем окне. Проверка: окно 1920×1080 по центру справа от панели, затем на прежнем месте прежнего размера.
- [ ] 5.2 Shift+Super+Enter дважды. Проверка: окно развёрнуто с отступами 10 px, затем на прежнем месте.
- [ ] 5.3 Shift+Super+Delete над окном, принятым в workspace. Проверка: окно уходит из workspace (закрывается, если других workspace у него нет).
- [ ] 5.4 Super+Backspace при карточке уведомления. Проверка: действие уведомления выполнено, запись удалена из истории.
- [ ] 5.5 Shift+Super+Backspace. Проверка: история уведомлений пуста, счётчик на плитке исчез.

## 6. Синхронизация и архивация

- [x] 6.1 Сверка дельт с основными спецификациями после архивации изменений из раздела «Порядок архивации» `proposal.md`: правки этого изменения перенесены на актуальный текст требований. Проверка: `openspec validate enter-backspace-keys --strict`.
- [x] 6.2 Синхронизация основных спецификаций с дельтами. Проверка: `rg -n 'Super\+Backspace' openspec/specs` находит только клавиши уведомлений, `rg -n 'Alt\+Super\+Enter|Super\+Ctrl\+Enter' openspec/specs` находит только правило о свободных сочетаниях в hyprland-binds.
- [ ] 6.3 Архивация `openspec archive enter-backspace-keys -y`.
