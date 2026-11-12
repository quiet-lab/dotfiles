## 1. Сессия

- [x] 1.1 Сценарий `herdr-prestart`: убрать `claude update` и `herdr update`, перенумеровать шаги, `--dry-run` печатает два шага (D1, D2).
- [x] 1.2 `herdr-prestart.service`: описание, комментарий, `TimeoutStartSec=30` (D3); комментарий `workspaced.service`.
- [x] 1.3 `chezmoi apply` файлов задачи, `systemctl --user daemon-reload`.

## 2. Проверки

- [x] 2.1 `systemd-analyze --user verify`; `systemctl --user show workspaced.service -p After -p Wants` без юнита обновлений.
- [x] 2.2 `herdr-prestart --dry-run`.
- [x] 2.3 `herdr-prestart.service` запущен вручную: ExecMain 17 мс (без вызовов обновлений сценарий от сети не зависит).
- [ ] 2.4 Проверка перезагрузкой: `workspaced.service` стартует без ожидания сети — в `todo.md`, строка о чистом старте herdr.

## 3. Спецификации и документация

- [x] 3.1 `docs/host-state.md`, `docs/package-sources-plan.md`, `todo.md`.
- [x] 3.2 `openspec validate --strict`, ревью, архивация.
