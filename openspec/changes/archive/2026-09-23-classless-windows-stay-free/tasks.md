## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `daemon.rs`: `classless`; проверка в `join_window` (`Free::NoClass`), `matcher_fits`, `Pending::matches`, `Daemon::on_open`; `save.rs`: пропуск окна без класса в `save_workspace` (решение D1)
- [x] 1.2 `daemon.rs`: `start` и `launch_dir` — запуск с полным текстом ошибки и домашним каталогом вместо отсутствующего; ими пользуются `Daemon::spawn` и `Daemon::spawn_foreign` (решение D2)
- [x] 1.3 `daemon.rs`: `Daemon::raise_on` продолжает поднятие после сбоя запуска; `session.rs`: `load` продолжает загрузку после сбоя запуска и поднятия (решение D2)
- [x] 1.4 `daemon.rs`: `join_window` получает командную строку, `same_program` — имя прежней записи только той же программе (решение D3)
- [x] 1.5 `daemon.rs`: `drop_extra_app` — запись с командой снимается во всех workspace, запись о месте — в активном; `Daemon::detach` пользуется ею (решение D3)
- [x] 1.6 `daemon.rs`: `launchable` в `proc_info`; `session.rs`: приведение команд снимка в `spawn_missing_foreign` и `same_window` (решение D4)
- [x] 1.7 Модульные тесты `classless_windows_stay_free`, `same_class_of_another_program_gets_its_own_name`, `detach_drops_session_app_in_every_workspace`, `launchable_command_from_proc`, `launch_failure_names_command_and_directory`, `session_plan_leaves_classless_windows_free`
- [x] 1.8 Сборка и проверки: `cargo test` — 84 теста проходят, `cargo clippy --all-targets` без предупреждений, `cargo build --release`
- [x] 1.9 Коммит `3f78938` в ветвь master, отправлен в `origin`

## 2. Проверка командами (агент)

- [x] 2.1 Перезапуск `workspaced.service`: снимок восстановлен, запись Steam из снимка запущена абсолютным путём `/home/mne/.local/share/Steam/ubuntu12_64/steamwebhelper` (окна процесс без Steam не открывает — предупреждение прежнее)
- [x] 2.2 `workspaced raise surf --desktop 2`: `surf` активен на столе 2 со всеми окнами, `work` — на столе 1, композитор на столе 2, как до перезапуска; журнал без ошибок
- [x] 2.3 Окно без класса вызывается только нажатием Shift+Esc в браузере, поэтому правило проверено модульными тестами

## 3. Спецификация и документация

- [x] 3.1 Дельты `ws-daemon` («Посторонние окна», «Захват открытых окон приложения», «Поднятие workspace на столе», «Отделение окна») и `ws-sessions` («Файлы сессий», «Дополнительные приложения сессии»); `openspec validate classless-windows-stay-free --strict` проходит
- [x] 3.2 `AGENTS.md`: окна без класса остаются свободными всегда
