## Why

В оболочке bash с ble.sh, в yazi, Neovim, fzf, atuin и television у каждой
программы и у каждого её режима свои горячие клавиши, часть из них
переназначена в `~/.blerc`, `dot_bashrc` и конфигах программ. Подсказки по
месту нет: панель Quickshell (спецификация `qs-keys-help`, Shift+Super+/)
показывает только цепочки композитора. Пользователь принял решения 1–9
записки задачи keys-help и дополнение из раздела «Переданные» её правил:
по клавише Ctrl+Alt+Shift+/ делить текущую панель herdr и в нижней трети
показывать клавиши того, что сейчас на переднем плане верхней части, в его
текущем режиме, с пользовательской конфигурацией порядка и видимости
записей; для программ без манифеста — извлекать клавиши универсальным
извлекателем, а не найденные — записывать в файл неизвестных программ
для разбора.

## What Changes

- Плагин herdr `quiet-lab.keys-help` в каталоге под chezmoi
  (`dot_config/herdr/plugins/keys-help`): манифест `herdr-plugin.toml`
  с действием `toggle` и панелью `viewer`, проект Rust (ядро, просмотрщик,
  декларативные извлекатели таблиц), сборка `cargo build --release`
  в `[[build]]` манифеста и сценарием chezmoi `run_onchange_` при
  изменении исходников, регистрация `herdr plugin link`.
- Клавиша `ctrl+alt+shift+slash` в `dot_config/herdr/config.toml`
  (`[[keys.command]]`, `type = "plugin_action"`): открывает под панелью
  в фокусе панель просмотрщика высотой в треть (не меньше 5 строк
  содержимого), повторное нажатие закрывает её.
- Контекст — строка `<программа>` или `<программа>.<режим>`
  (`ble.vi_imap`, `ble.vi_nmap`, `ble.isearch`, `yazi.manager`,
  `nvim.normal`, `atuin.search`, `fzf`, `<команда>.generic`).
- Поставщики контекста, все по событиям, пишут записи в каталог
  `$XDG_RUNTIME_DIR/herdr-keys-help/panes/<HERDR_PANE_ID>/`: модуль ble.sh
  (`dot_config/blesh/keys-help.bash`, подключается из `dot_blerc`) — смена
  keymap, запуск программы (`PREEXEC`), виджеты `-x`/`-c`, возврат
  (`PRECMD`); модуль Neovim (`dot_config/nvim/lua/keys_help.lua`) —
  `VimEnter`/`ModeChanged`/`VimLeavePre`; yazi — по ответу на открытый
  вопрос о слое (design.md, D9). Просмотрщик ждёт их через inotify,
  следует за панелью в фокусе своего workspace подпиской herdr
  `events.subscribe` (`pane.focused`, `pane.updated`, `pane.closed`,
  `pane.moved`, `layout.updated`, `pane.output_matched`), выход процессов
  отслеживает через pidfd.
- Манифест программы — один TOML-файл в `manifests/` плагина: как
  распознать программу и режим (поставщик, процесс, команда оболочки,
  заголовок, экран), откуда взять таблицу (декларативные источники
  `regex`, `toml`, `json`, `static` по выводу команды, файлу или
  переменной окружения), группы, описания и происхождение записей.
  Манифесты первой очереди: ble.sh, fzf, atuin, television, yazi, Neovim.
  Ядро имён программ не знает.
- Универсальный манифест-извлекатель `generic.toml` для любой программы
  без своего манифеста: разделы о клавишах в `man`, вывод `--help`,
  известные файлы конфигурации клавиш; контекст `<команда>.generic`,
  происхождение `generic`. Порядок: манифест программы → универсальный
  извлекатель → запись в файл неизвестных программ
  `$XDG_STATE_HOME/herdr-keys-help/unknown-programs.toml` (команда,
  счётчик запусков, дата последнего, без повторов).
- Хук `SessionStart` Claude Code в проекте dotfiles
  (`.claude/settings.json`, сценарий `.claude/hooks/keys-help-unknown.sh`)
  печатает список неизвестных программ при старте сессии; порядок разбора
  — в `docs/keys-help.md`.
- Конфигурация представления `view.toml` под chezmoi: `[defaults]`,
  `[context."<шаблон>"]` с полями `order`, `hide`, `hide_groups`, `pin`,
  `only_modifiers`, `show_origin`, записи `[entry."<контекст>"."<клавиша>"]`;
  наследование «умолчания → программа → режим», шаблоны `yazi.*`.
  Клавиши просмотрщика «скрыть запись» и «скрыть группу» дописывают файл.
- `dot_config/herdr/config.toml`, `[ui]`: `pane_outer_borders = false`,
  `pane_gaps = false`.
- `dot_config/wezterm/wezterm.lua`: `enable_kitty_keyboard = true`
  с проверкой регрессий привязок (ведёт отдельный исполнитель).
- Документация: `docs/keys-help.md`, строка `docs/README.md`, абзац
  `CLAUDE.md`, запись в `docs/decisions/`.

## Capabilities

### New Capabilities

- `herdr-keys-help`: подсказка горячих клавиш по контексту в нижней панели
  herdr — плагин, поставщики контекста, манифесты программ, универсальный
  извлекатель, файл неизвестных программ, конфигурация представления.

### Modified Capabilities

Нет: спецификация `qs-keys-help` (клавиши композитора) не меняется.

## Impact

- Новые файлы под chezmoi: `dot_config/herdr/plugins/keys-help/**`,
  `dot_config/blesh/keys-help.bash`, `dot_config/nvim/lua/keys_help.lua`,
  `dot_config/herdr/keys-help/view.toml` (символическая ссылка в источник),
  сценарий `run_onchange_after_build-herdr-keys-help.sh.tmpl`,
  `.claude/hooks/keys-help-unknown.sh`.
- Правки: `dot_blerc` (подключение модуля), `dot_config/nvim/lua/config/autocmds.lua`,
  `dot_config/herdr/config.toml` (`[[keys.command]]`, `[ui]`),
  `dot_config/wezterm/wezterm.lua`, `.claude/settings.json`,
  `.chezmoiignore`.
- Зависимости сборки: `cargo` (есть), crates `serde`, `toml`,
  `toml_edit`, `serde_json`, `regex`, `inotify`, `rustix`/`nix`
  (pidfd, signalfd, poll), `crossterm`.
- Форк herdr не меняется, если клавиша доходит после включения протокола
  kitty в wezterm (решение 2 записки).
- Конфиги yazi, atuin и television только читаются.
