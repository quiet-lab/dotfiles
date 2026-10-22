## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `daemon.rs`: `arrange_layout` снимает раскладку через `State::reset_layout` и записывает главное приложение (D1), комментарии к `arrange` и `arrange_layout`, `README.md`. Проверка: тест `arrange_resets_moved_keeps_swap` заменён тестами `arrange_restores_config_layout` (обмен herdr ↔ neovide отменяется, `main` — herdr, `moved` пуст) и `arrange_keeps_session_app_rect` (место записи сессии — её прямоугольник, после снятия записи прямоугольник у приложения конфига не остаётся).
- [x] 1.2 Сборка и проверки: `cargo test -- --test-threads=8` — 171 тест проходит, `cargo clippy --all-targets` без замечаний, `cargo build --release`. `cargo fmt` в проекте не используется (строки длиннее ширины rustfmt по умолчанию).

## 2. Спецификации и документация

- [x] 2.1 Дельта `ws-daemon`: требование «Расстановка по команде» заменено требованием «Возврат раскладки к конфигу по команде» (D2); дельты старого требования в `live-layout` и `work-area-center` сняты, ссылки на него там переименованы, решение D10 `live-layout` помечено пересмотренным. Проверка: `openspec validate --strict` для всех трёх изменений.
- [x] 2.2 `docs/window-model.md`, `AGENTS.md` (он же `CLAUDE.md`), комментарий к записи `arrange` в `dot_config/workspaced/config.toml`; `chezmoi apply ~/.config/workspaced/config.toml`, `workspaced check`.

## 3. Проверка вживую командами (агент)

- [x] 3.1 `systemctl --user restart workspaced.service`, журнал без ошибок. На столе 1 в `work`: `workspaced key 'SUPER+E'` — `main` neovide, у herdr изменённое место 3055,10; `workspaced arrange` — `cells` из файла (herdr `center`, neovide `right`, chromium `left`, chrome `right`), `main` herdr, `moved` пуст; по `hyprctl clients -j` herdr в 1125,10, neovide и chrome в 3055,10, chromium в -805,10, все 1920×2140. Фокус возвращён окну herdr, активному до проверки.

## 4. Проверка вживую (пользователь)

Нет: всё проверяемое без физических нажатий проверено командами, привязка Ctrl+Super+Пробел вызывает ту же команду `workspaced arrange`.
