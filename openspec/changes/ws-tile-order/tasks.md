## 1. Панель

- [x] 1.1 `tiles/Workspaces.qml`: `wsListFor` возвращает workspace стола в порядке списка демона, без перестановки активного вперёд (решение D1)
- [x] 1.2 `tiles/Workspaces.qml`: `itemsFor` собирает ряд «все workspace, окна активного workspace, свободные окна»; адреса окон неактивных workspace исключаются из свободных окон (решения D1, D2)
- [x] 1.3 `tiles/Workspaces.qml`: подсказка к иконке workspace — «активен/неактивен на столе N» (решение D3), комментарии обновлены
- [x] 1.4 `chezmoi apply ~/.config/quickshell/panel`, перезапуск `quickshell-panel.service`. Проверка: журнал без ошибок QML

## 2. Проверка командами (агент)

- [x] 2.1 `workspaced raise surf --desktop 1`, `workspaced raise work --desktop 1`, `workspaced next`: список `desktops["1"].workspaces` в `workspaced status --json` остаётся `[surf, work]`, меняется только признак `active`
- [x] 2.2 Окна неактивного workspace `surf` по `hyprctl clients -j` лежат на `special:pool`, на столе их нет

## 3. Документация

- [x] 3.1 `AGENTS.md` и `docs/`: описания порядка ряда плитки приведены к новому

## 4. Проверка пользователем

- [ ] 4.1 Вид плитки стола при переключении workspace: иконки workspace стоят на своих местах, неактивный затенён, иконок его окон нет (проверяет пользователь)
