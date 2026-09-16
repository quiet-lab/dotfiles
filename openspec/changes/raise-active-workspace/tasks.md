## 1. Демон workspaced (`~/work/pets/workspaced`)

- [x] 1.1 `daemon.rs`: `active_desktop_of`, стол по умолчанию в `raise`, вызов без стола в пути цепочки приложения по списку текущего стола; `cargo test`, `cargo build --release`, перезапуск `workspaced.service`
- [x] 1.2 Проверка командой: при `surf`, активном на столе 2, `workspaced raise surf` со стола 1 переводит на стол 2, окна не переезжают, фокус у главного окна

## 2. Проверка вживую (пользователь)

- [ ] 2.1 Со стола 1 нажать `Super+Tab s`: переход на стол 2 к `surf`; `Super+Y` со стола 1 — то же с фокусом на Яндекс.Браузере

## 3. Спецификации и документация

- [x] 3.1 Дельта ws-daemon, `openspec validate raise-active-workspace --strict`
- [x] 3.2 AGENTS.md
