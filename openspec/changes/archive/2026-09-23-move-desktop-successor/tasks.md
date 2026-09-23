## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `state.rs`: поле `State::prev_active` — прежний активный workspace каждого стола, только в памяти (решение D2)
- [x] 1.2 `daemon.rs`: `assign_desktop` записывает вытесненный workspace в историю стола; стол, с которого workspace ушёл, историю не меняет
- [x] 1.3 `daemon.rs`: чистая функция `successor` — история, затем предыдущий по списку по кругу, затем преемника нет (решения D1, D3)
- [x] 1.4 `daemon.rs`: `Daemon::raise_on(ws, desktop, focus)`; при `focus = false` композитор не переходит на стол, главное окно фокуса не получает, запускаемые приложения тоже (решение D4)
- [x] 1.5 `daemon.rs`: `Daemon::move_desktop` выбирает преемника по списку и истории до переноса и поднимает его на прежнем столе после переноса
- [x] 1.6 Модульные тесты `assign_desktop_records_previous_active`, `successor_prefers_previous_active`, `successor_without_history_takes_previous_in_list`, `successor_ignores_stale_history`, `successor_none_for_single_workspace`
- [x] 1.7 Сборка и проверки: `cargo test` — 78 тестов проходят, `cargo clippy --all-targets` без предупреждений, `cargo build --release`
- [x] 1.8 Коммит `da04826` в ветвь master, отправлен в `origin`

## 2. Проверка командами (агент)

- [x] 2.1 Перезапуск `workspaced.service` с новым бинарником; сессия восстановлена: список стола 1 — `surf`, `work`, активен `work`
- [x] 2.2 `workspaced raise surf --desktop 1`, затем `workspaced raise work --desktop 1`: история стола 1 — `surf`
- [x] 2.3 `workspaced move-desktop 5`: `work` на столе 5, композитор на столе 5, фокус у herdr; на столе 1 активен `surf`, окна Яндекс.Браузера и двух Chrome вернулись с `special:pool` на стол 1 в прежние прямоугольники; журнал: «стол 1: активным становится surf»
- [x] 2.4 `workspaced move-desktop 1` со стола 5: `work` активен на столе 1, окна `surf` на `special:pool`, список стола 1 — `surf`, `work`; стол 5 пуст, журнал: «стол 5: других workspace нет, активного не остаётся»
- [x] 2.5 Состояние до проверки восстановлено: `surf` на столе 2, `work` на столе 1, композитор на столе 1, `workspaced arrange`; журнал демона без ошибок

## 3. Спецификация и документация

- [x] 3.1 Дельта `ws-daemon`: требования «Перенос workspace на стол» и «Поднятие workspace на столе»; `openspec validate move-desktop-successor --strict` проходит
- [x] 3.2 `AGENTS.md` и `docs/window-model.md` описывают преемника на прежнем столе
