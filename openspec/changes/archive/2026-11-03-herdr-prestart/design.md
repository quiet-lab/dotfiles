## Context

- herdr стоит пакетом AUR `herdr-bin` в `/usr/bin`. `herdr update`
  заменяет бинарник на месте и в `/usr/bin` без root откажет; `yay` от root
  не работает, пакет AUR собирается `makepkg` от пользователя и ставится
  `pacman -U` от root. Правила sudoers не расширяются (`~/.claude/CLAUDE.md`,
  «Повышение привилегий»).
- Адреса AUR (`aur.archlinux.org`) входят в набор `zones` туннеля `amn0`
  (подсети США). Соединение, помеченное в туннель, устанавливается, но
  рукопожатие TLS не проходит: ответ сервера не укладывается в MTU туннеля
  (`docs/open-questions/amn0-tcp-mss.md`). С `curl --interface amn0` запрос
  проходит за доли секунды. Бинарник релиза herdr скачивается с GitHub
  напрямую.
- Claude Code установлен native (`~/.local/share/claude/versions/`),
  автообновление в `~/.claude.json` выключено. `herdr integration install
  claude` переписывает `~/.claude/hooks/herdr-agent-state.sh` и группу
  `SessionStart` в `~/.claude/settings.json`, остальные хуки не трогает.
- herdr 0.9.5 при старте сервера читает `~/.config/herdr/session.json`;
  если файла нет, создаёт одно пространство в каталоге запуска.
  Свои копии он держит в `session-snapshots/` и `session-backups/`.
- herdr открывает демон workspaced окном стартового workspace
  (`[apps.herdr]`, юнит `workspaced.service` в `hyprland-session.target`).
- Таймеры и опрос запрещены (`docs/decisions/0007-no-timers.md`).

## Goals / Non-Goals

**Goals:**

- herdr, Claude Code и интеграция между ними обновлены до запуска herdr.
- herdr стартует одним пространством в монорепозитории, Claude Code сам
  не запускается.

**Non-Goals:**

- Собственная сборка herdr в `~/.local/bin` — после форка herdr.
- Включение автообновления Claude Code.

## Decisions

### D1. Пакет AUR, пока нет форка

Обновление herdr — системный юнит `herdr-update.service` при загрузке:
сравнение версии в AUR с установленной, сборка `makepkg` от пользователя
и `pacman -U`. `herdr update` отвергнут: бинарник в `/usr/bin` без root
не заменить, а замена в обход pacman ломает учёт пакета. Пакет
пересобирается из PKGBUILD AUR без просмотра изменений — то же доверие
к сопровождающему пакета, что у `yay`.

Условие пересмотра: появился форк herdr со своей установкой
в `~/.local/bin`; тогда пакет удаляется, юнит и `system/herdr-update/`
удаляются, обновление переходит в пользовательский юнит подготовки.

### D2. Порядок и сроки при загрузке

`After=network-online.target awg-quick@amn0.service`, `Before=greetd.service`,
`WantedBy=greetd.service`, как у `tunnels-before-login.service`: туннель
нужен для AUR, но юнит его не поднимает (без `Wants`). Срок задания
`JobTimeoutSec=240` с `JobTimeoutAction=none` — 105 с ожидания туннелей
и втрое замеренные 44 с обновления; по сроку systemd снимает только
задание, работа юнита продолжается после входа. Предел всей работы —
`TimeoutStartSec=180`. Зависшее скачивание makepkg ограничено своей
добавкой к настройкам makepkg: `--connect-timeout 15`, обрыв ниже
10 КБ/с дольше 30 с.

### D3. Запросы к AUR привязаны к amn0

Сценарий вызывает `curl --interface amn0` для RPC и снимка PKGBUILD:
размер сегмента TCP тогда выбирается по MTU туннеля. Правка таблицы
`inet amn` (ограничение размера сегмента для всего трафика туннеля)
отвергнута в этом изменении: она меняет весь трафик туннеля и вынесена
в открытый вопрос. Без `amn0` запрос не проходит, юнит пишет
«AUR недоступен» и завершается.

### D4. Подготовка в сессии

Пользовательский юнит `herdr-prestart.service` (oneshot, `RemainAfterExit`,
`PartOf` и `WantedBy` `hyprland-session.target`); `workspaced.service`
получает `After=` и `Wants=` на него: неудача подготовки демон
не останавливает. Шаги — сценарий `herdr-prestart`: ошибка шага пишется
в журнал и не останавливает следующий.

### D5. Чистый старт переименованием session.json

При незапущенном сервере herdr `session.json` переименовывается
в `session.json.<дата-время>` рядом, хранится не больше десяти копий;
`session-backups/` и `session-snapshots/` принадлежат herdr и не трогаются.
При запущенном сервере файл не трогается: его перезапишет сервер.
Признак запущенного сервера — строка `status: running` у
`herdr status server`. `resume_agents_on_restore = false` в конфиге herdr
дополнительно не даёт запускать агентов, если сессия всё же восстановлена.

## Risks / Trade-offs

- Обновление, доделанное после входа, меняет `/usr/bin/herdr` во время
  запуска herdr. Запущенный процесс работает со старым файлом, новая
  версия действует со следующего запуска сервера.
- PKGBUILD AUR не проверяется перед сборкой (D1).
- `~/.claude/settings.json` под chezmoi: когда новая версия herdr меняет
  свою группу `SessionStart`, `herdr integration install claude` правит файл
  в `$HOME`, и `chezmoi status` показывает расхождение до
  `chezmoi re-add ~/.claude/settings.json`. Без новой версии интеграция файл
  не меняет.
