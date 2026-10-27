## Why

Сочетания с клавишей Enter заняты уведомлениями (Super+Enter,
Shift+Super+Enter, Super+Ctrl+Enter, Super+Ctrl+Alt+Enter) и окном
1920×1080 (Alt+Super+Enter), а Super+Backspace — отделением окна
от workspace. Пользователь переназначает их: Enter отдаётся размеру окна,
Backspace — разбору уведомлений, отделение окна переходит к Delete рядом
с закрытием окна. Окно 1920×1080 при этом получает возврат прежней
геометрии, как у развёртывания.

## What Changes

- Shift+Super+Delete (`SUPER+SHIFT+Delete`) — отделить активное окно
  от активного workspace текущего стола (`action = "detach"`); прежнее
  сочетание Super+Backspace освобождается. Super+Delete по-прежнему
  закрывает окно.
- Super+Backspace (`SUPER+BackSpace`) — действие по умолчанию верхней
  карточки уведомлений и удаление её из истории (`invokeOldest`), прежде
  Shift+Super+Enter.
- Shift+Super+Backspace (`SUPER+SHIFT+BackSpace`) — очистить историю
  уведомлений целиком (`clear`), прежде Super+Ctrl+Alt+Enter.
- Новая команда демона `workspaced fit <ширина>x<высота>` и действие
  `[[binds]]` `action = { fit = "<ширина>x<высота>" }`: окно плавающее,
  заданного размера, по центру рабочей области (размер больше области
  урезается до области развёртывания `maximize`); повторный вызов
  возвращает прежние положение и размер. Запомненная геометрия общая
  с командой `maximize`.
- Super+Enter (`SUPER+Return`) — `fit 1920x1080`.
- Shift+Super+Enter (`SUPER+SHIFT+Return`) — `maximize`, второе сочетание
  рядом с Alt+Super+PageUp.
- **BREAKING** Удаляются сочетания Super+Enter с `dismissOldest` (функция
  IPC панели остаётся без клавиши), Super+Ctrl+Enter с `closeAll` (то же
  действие остаётся на Ctrl+Shift+Пробел), Super+Ctrl+Alt+Enter
  и Alt+Super+Enter с тремя диспетчерами композитора. Других сочетаний
  с Enter, кроме Super+Enter и Shift+Super+Enter, сессия не занимает;
  Ctrl+Enter по-прежнему свободен.
- Backspace и Escape внутри режимов цепочек (Super+Tab, Ctrl+Super+S,
  Super+S) действуют как прежде.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `hyprland-binds`: «Раскладка клавиш сессии» — новые сочетания, правило
  о свободных сочетаниях с Enter, сценарии.
- `ws-config`: «Цепочки клавиш и привязки» — действие `fit` с проверкой
  размера; сценарий отделения окна на Shift+Super+Delete.
- `ws-daemon`: новое требование «Окно заданного размера по центру»;
  «Развёртывание окна» — общая с `fit` запомненная геометрия; «Отделение
  окна» — сценарии на Shift+Super+Delete.
- `qs-notifications`: «Управление уведомлениями с клавиатуры» — Super+Backspace
  и Shift+Super+Backspace, сочетаний с Enter у уведомлений нет.
- `qs-workspaces`: «Иконки workspace в плитке стола» — сценарий отделения
  окна на Shift+Super+Delete.
- `ws-sessions`: «Дополнительные приложения сессии» — сценарий отделения
  окна на Shift+Super+Delete.

## Порядок архивации

Требования, которые правят и другие активные изменения, взяты из их дельт:
«Раскладка клавиш сессии» — из `toggle-windows` (в ней уже учтены
`work-area-center`, `sticky-chains` и `chains-sticky`; строка Super+Tab s —
из `openspec/specs/`), «Цепочки клавиш и привязки» — из `shared-app-chain`
(включает правки `chains-sticky`), «Дополнительные приложения сессии» —
из `session-windows-transient` (включает правки `live-layout`). Остальные
требования — из `openspec/specs/`. Поэтому изменение архивируется после
`toggle-windows`, `shared-app-chain`, `session-windows-transient` и тех
изменений, после которых архивируются они; перед архивацией дельты
сверяются с основными спецификациями на тот момент.

## Impact

- Демон `~/work/pets/workspaced`: команда `fit` (`main.rs`, `client.rs`,
  `daemon.rs` — общая с `maximize` запомненная геометрия), действие `fit`
  и проверка размера (`config.rs`), привязка и строка перечня (`keys.rs`,
  `keys_help.rs` — описание и группа «Окна»), модульные тесты.
- Конфиг `dot_config/workspaced/config.toml`, раздел `[[binds]]`.
- Документы: `AGENTS.md` (он же `CLAUDE.md`), `docs/window-model.md`.
- Панель Quickshell не меняется: функции IPC `notifications` остаются
  прежними.
