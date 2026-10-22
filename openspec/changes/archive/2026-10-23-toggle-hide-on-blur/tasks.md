## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `daemon.rs`: чистые функции `toggle_app_of` и `blur_step` (D1–D4), поле `Daemon::toggle_focused`, метод `toggle_blur`, вызов в `on_focus` до прежней логики с окном, спрошенным у композитора (D4), общий метод скрытия `hide_toggle` для клавиши и потери фокуса (D5), строка журнала о скрытии. Коммит демона `5aee0c7`.
- [x] 1.2 Тест `toggle_hides_on_blur`: обычное окно и пустой адрес — скрыть; второе окно Telegram, в том числе без тега, — не потеря; `termfilechooser`, `pinentry-qt`, окно без класса — не потеря, после них возврат в Telegram ничего не прячет, переход в herdr прячет; без окна переключателя в фокусе прятать нечего. `CARGO_BUILD_JOBS=16 cargo test -- --test-threads=8` — 182 теста проходят, `cargo clippy --all-targets` без замечаний, `cargo build --release`. В `README.md` демона переключатели не описаны, правка не нужна.

## 2. Спецификации, конфиг и документация

- [x] 2.1 Дельта ws-daemon: новое требование «Скрытие окна-переключателя при потере фокуса» (`ADDED`: требование «Окно-переключатель» пока только в дельте `toggle-windows`). В дельте ws-daemon изменения `toggle-windows` исключение о `special:pool` ссылается на новое требование, шаг 2 клавиши поясняет, когда окно стоит на столе без фокуса, сценарии «Окно под другими окнами», «Окно на другом столе», «Поднятие workspace не трогает переключатель» переписаны под новое правило; строка Super+T дельты hyprland-binds дополнена; в `design.md` `toggle-windows` (D5) — примечание. Проверка: `openspec validate --strict` для всех активных изменений.
- [x] 2.2 `dot_config/workspaced/config.toml`: комментарий у `[apps.telegram]` (размер 1500×1500, скрытие при потере фокуса). `chezmoi apply ~/.config/workspaced/config.toml`, `workspaced check` — конфиг корректен, демон перечитал конфиг.
- [x] 2.3 `docs/window-model.md` (раздел 2.8, строка таблицы требований ws-daemon, раздел 5), `AGENTS.md` (он же `CLAUDE.md`), `todo.md`.

## 3. Проверка вживую командами (агент)

- [x] 3.1 `systemctl --user restart workspaced.service`, журнал без ошибок и предупреждений. До проверки: Telegram `0x5642217f5a90` на `special:pool`, фокус у herdr `0x56422161a7a0`. События композитора записывались из `.socket2.sock`.
- [x] 3.2 `workspaced key 'SUPER+T'`: окно Telegram на столе 1 в 1335,330 1500×1500 с фокусом; события `movewindowv2`, `activewindowv2` Telegram, пустого адреса между ними нет. Фокус herdr диспетчером `hl.dsp.focus({ window = "address:0x56422161a7a0" })`: Telegram на `special:pool`, в журнале «окно-переключатель telegram: потеря фокуса (фокус у 0x56422161a7a0 (wezterm-herdr)) — спрятано».
- [x] 3.3 Исключение для окна из `ignore_classes`: при показанном Telegram запущен `zenity --info` (класс `zenity`) — фокус у zenity, Telegram остаётся на столе 1; фокус обратно Telegram — остаётся; снова zenity — остаётся; фокус herdr — Telegram на `special:pool`. Окно zenity закрыто по pid.
- [x] 3.4 Лаунчер rofi (`rofi -show drun`, слой) при показанном Telegram: событий `activewindowv2` нет, Telegram остаётся; rofi закрыт по pid.
- [x] 3.5 Пустой адрес: при показанном Telegram переход на пустой стол 2 — событие `activewindowv2>>` с пустым адресом, Telegram на `special:pool`, в журнале «потеря фокуса (фокуса нет ни у одного окна)» (строка уточнена после проверки); возврат на стол 1.
- [x] 3.6 Активация спрятанного окна: `hl.dsp.focus` по адресу Telegram на `special:pool` — события `activewindowv2` Telegram, `activespecial>>special:pool`, при закрытии `special:pool` промежуточное `activewindowv2` другого окна стола, затем `movewindowv2` и `activewindowv2` Telegram; окно на столе 1 с фокусом, `specialWorkspace` пуст, промежуточное событие его не спрятало (D4).
- [x] 3.7 Повторная клавиша `workspaced key 'SUPER+T'` прячет окно, как прежде (`Hide`). В конце Telegram возвращён на `special:pool`, фокус — herdr `0x56422161a7a0`, как до проверки.

## 4. Проверка вживую (пользователь)

Нет: клик по окну и привязка Super+T дают те же события `activewindowv2` и ту же команду `workspaced key`, что проверены командами; окно выбора файла проверено окном того же списка `ignore_classes` (`zenity`), а второе окно Telegram — модульным тестом.
