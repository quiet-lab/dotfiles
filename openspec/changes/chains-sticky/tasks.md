## 1. Демон workspaced

- [x] 1.1 `src/keys.rs`: дерево многозвенных цепочек `auto_nodes` по ключу сравнения звеньев, состояния `StickyNode` с признаком `auto`, у `StickyBind` модификаторы, флаги и исходная привязка; проверки звеньев Escape и BackSpace, неразличимых звеньев и совпадения имени подкарты с цепочкой с выходом; проверка состояний после проверки совпадения цепочек (решения D1–D4) — 23.09.2026
- [x] 1.2 `src/keys.rs`, `to_lua`: прямые привязки одиночных сочетаний, одна привязка первого сочетания на режим, подкарты режимов тем же `emit_sticky`, что у разделов `[sticky.*]`: звено без модификаторов с `ignore_mods`, с модификаторами — точно, флаги записи у последнего звена; подкарт `ws:…` нет, закрытие устаревшей подкарты узнаёт `ws:` и `ws-sticky:` (решения D2, D3) — 23.09.2026
- [x] 1.3 `src/keys.rs`, `to_list`: флаг `exit` у многозвенных цепочек; `src/main.rs`: строки режимов в `workspaced check` (решение D5) — 23.09.2026
- [x] 1.4 `src/keys_help.rs`: описания клавиш режимов из описаний привязок (`binding_desc`), «Далее: …» у промежуточного звена, в разделе `sticky` ключ и подпись с модификаторами (решение D5) — 23.09.2026
- [x] 1.5 Тесты: прежние тесты цепочек переписаны на подкарты `ws-sticky:…`; новые `chains_become_modes`, `chain_mode_errors` (`keys.rs`), `chain_modes_in_sticky_section` (`keys_help.rs`); всего 156 — 23.09.2026
- [x] 1.6 `cargo test`, `cargo clippy --all-targets -- -D warnings`, `cargo build --release`; `README.md` демона — абзац о режимах многозвенных цепочек; коммит `1e395ff` и push в `master` — 23.09.2026

## 2. Конфиг и панель

- [x] 2.1 `dot_config/workspaced/config.toml`: комментарии о префиксе Super+Tab и шапка раздела привязок — многозвенная цепочка задаёт режим; положение карточки в комментарии раздела `[sticky]`; `chezmoi apply`, `workspaced check` проходит и печатает режимы `SUPER+CTRL+s` и `SUPER+TAB` — 23.09.2026
- [x] 2.2 `dot_config/quickshell/panel`: комментарии `KeyChains.qml`, `KeyChainsWindow.qml`, `shell.qml` (решение D6); `chezmoi apply`, `chains state` отвечает — 23.09.2026

## 3. Проверка командами (агент)

- [x] 3.1 `hyprctl reload config-only`; `hyprctl binds -j`: подкарты `ws-sticky:SUPER+TAB` (`Tab`, `s`, `w` с маской 0) и `ws-sticky:SUPER+CTRL+s` (`s`, `w` с маской 68), в каждой `BackSpace`, `Escape` и одна привязка `catch_all: true`; подкарт `ws:…` нет; в корне Super+Tab и Ctrl+Super+S открывают режимы; `keys --lua | luac -p -` проходит, копия `keys.lua` совпадает с выводом — 23.09.2026
- [x] 3.2 Событие `submap` и индикатор: `hl.dsp.submap("ws-sticky:SUPER+TAB")` — `submap>>ws-sticky:SUPER+TAB`, `chains state` «shown ws-sticky:SUPER+TAB rows=3 card=right-bottom margins=10,10 556x238»; `submap("reset")` — `submap>>`, «hidden»; `ws-sticky:SUPER+CTRL+s` — «shown … rows=2 … 710x197», затем «hidden»; после проверок подкарта сброшена, стол 1, фокус herdr — 23.09.2026
- [x] 3.3 `keys --json`, раздел `sticky`: `ws-sticky:SUPER+TAB` с путём «Super+Tab» и клавишами «Tab — Следующий workspace стола», «s — Поднять workspace surf», «w — Поднять workspace work»; `ws-sticky:SUPER+CTRL+s` с путём «Ctrl+Super+S» и клавишами «Ctrl+Super+S — Записать снимок сессии», «Ctrl+Super+W — Записать workspace в конфиг», у всех `exit: true`; `keys --list`: пять цепочек с флагом `exit` — 23.09.2026
- [x] 3.4 `openspec validate chains-sticky --strict` — 23.09.2026

## 4. Проверка пользователем (нажатия)

- [ ] 4.1 Super+Tab: карточка «Super+Tab» с тремя клавишами в правом нижнем углу; при удержанном Super q поглощается, s поднимает `surf` и закрывает режим (сценарий «Карточка префикса и посторонняя клавиша»)
- [ ] 4.2 Super+Tab, затем w и Tab по отдельности: `work` поднимается, следующий workspace стола поднимается, режим закрывается
- [ ] 4.3 Ctrl+Super+S и, не отпуская Ctrl и Super, S: снимок сессии записан, режим закрыт; Ctrl+Super+S, затем W без модификаторов поглощается, Ctrl+Super+W записывает workspace (сценарий «Префикс сохранения»)
- [ ] 4.4 Ctrl+Super+S, Backspace и Ctrl+Super+S, Escape: ничего не сохраняется, карточка исчезает (сценарий «Отмена префикса»)

## 5. Документация и архивация

- [x] 5.1 `AGENTS.md`, раздел «Сессия Hyprland»: фраза «Префикс действий с workspace — Super+Tab (после него Super отпускается)» и описание команд сохранения — префиксы открывают режим с карточкой, Super можно не отпускать, Ctrl+Super+S и Ctrl+Super+W нажимаются с модификаторами, Backspace и Escape отменяют (правка вне этого прохода: файл правит основная сессия) — сделано 23.09.2026
- [ ] 5.2 Архивация `openspec archive chains-sticky -y` после `sticky-chains` (порядок — в `proposal.md`), затем `openspec validate --specs --strict`
