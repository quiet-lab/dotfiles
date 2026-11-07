## 1. Разбор и подтверждение

- [x] 1.1 Проба: экран множественного выбора не на последнем вопросе → `tests/fixtures/ask-q1-multi-next.txt`.
- [x] 1.2 `dialog.lua`: кнопка «Submit» или «Next», образец выделения по надписи.
- [x] 1.3 Тесты: `tests/dialog_spec.lua`, `tests/switch_spec.lua`. Проверка: оба печатают `ALL OK`.
- [x] 1.4 `docs/claude-input.md`, спецификация. Проверка: `openspec validate dialog-next-row --strict`.
- [ ] 1.5 Живая проверка: `:w` на экране пробы переводит карточку к следующему вопросу.
