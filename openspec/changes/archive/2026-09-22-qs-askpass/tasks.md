## 1. Конфигурация окна

- [x] 1.1 `dot_config/quickshell/askpass/shell.qml`: окно слоя `overlay`
      с пространством имён `askpass`, монопольным фокусом клавиатуры,
      без зарезервированной зоны, на мониторе в фокусе Hyprland
- [x] 1.2 `dot_config/quickshell/askpass/symlink_panel` с целью
      `../panel`: `Theme` и `Tile` подключаются модулем `qs.panel`,
      файлы панели не копируются и не правятся
- [x] 1.3 Содержимое окна: заголовок «SUDO», пояснение из
      `ASKPASS_MESSAGE` с переносом строк, поле ввода со значком показа
      набранного пароля, строка подсказки о клавишах; отступы и рамка —
      из `Theme`
- [x] 1.4 Enter отдаёт пароль (пустое поле ввод не завершает), Escape
      отменяет; ответ уходит в канал `ASKPASS_FIFO` через stdin
      дочернего процесса, тот же процесс снимает Quickshell

## 2. Обёртка sudo-askpass

- [x] 2.1 `dot_local/bin/handmade-scripts/executable_sudo-askpass`:
      каталог с правами 0700 в `$XDG_RUNTIME_DIR`, канал с правами
      0600, удаление каталога по `trap`
- [x] 2.2 Запуск `qs -c askpass` с переменными `ASKPASS_FIFO`
      и `ASKPASS_MESSAGE`; вывод Quickshell в stdout обёртки не
      попадает
- [x] 2.3 Разбор первой строки канала: `P` — печать пароля и код 0,
      `C` — код 1 без вывода, пустая строка — запасной путь
- [x] 2.4 Запасной путь pinentry-gtk сохранён и вызывается, когда `qs`
      недоступен, конфигурации нет, сессия не Wayland или окно
      завершилось, не ответив
- [x] 2.5 Ожидание ответа без срока и без опроса: канал открыт на
      чтение и запись, о завершении Quickshell сообщает пустая строка
      от фоновой группы команд

## 3. Композитор

- [x] 3.1 `dot_config/hypr/hyprland.lua`: правило слоя `askpass-blur`
      для пространства имён `askpass` с порогом `ignore_alpha = 0.2`,
      как у панели; `hyprctl reload config-only`, `hyprctl configerrors`
      пуст

## 4. Проверки в живой сессии

- [x] 4.1 `chezmoi apply`, `chezmoi status` без расхождений по
      `~/.config/quickshell/askpass`, `~/.local/bin/handmade-scripts/sudo-askpass`
      и `~/.config/hypr/hyprland.lua`
- [x] 4.2 Окно появляется: `hyprctl layers` показывает слой `askpass`
      на мониторе с курсором, в `hyprctl clients` его нет
- [x] 4.3 Ввод: набор идёт в поле без клика, Enter даёт код выхода 0
      и ровно одну строку в stdout — введённый пароль
- [x] 4.4 Отмена: Escape даёт код выхода 1, пустой вывод, окно
      исчезает, каталога с каналом в `$XDG_RUNTIME_DIR` не остаётся
- [x] 4.5 Пароль не утекает: в журнале пользователя и в журналах
      Quickshell тестового пароля нет
- [x] 4.6 Запасной путь: при намеренно сломанном `shell.qml` обёртка
      показывает pinentry-gtk
- [x] 4.7 Панель не затронута: `quickshell-panel.service` активен,
      новых ошибок в журнале нет

## 5. Документация

- [x] 5.1 `AGENTS.md`, раздел «Команды с правами root»: абзац про окно
      переписан — окно рисует Quickshell, pinentry остался запасным
      путём
- [x] 5.2 Дельты спецификаций `qs-askpass` (новая capability)
      и `hyprland-config`; `openspec validate qs-askpass --strict`
      проходит
