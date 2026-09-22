## 1. Пауза плееров силами VoxType

- [x] 1.1 Установить пакет `playerctl` (2.4.1-5.1 из `extra`), без него ключ
  `pause_media` ничего не делает
- [x] 1.2 `dot_config/voxtype/config.toml`: в разделе `[audio]` ключ
  `pause_media = true` с пояснением по-русски
- [x] 1.3 `chezmoi apply`, проверить, что ключ принят разбором конфига
  (строковое значение даёт ошибку «invalid type: string, expected
  a boolean» с указанием строки, неизвестный ключ такой ошибки не даёт),
  перезапустить `voxtype.service` и убедиться, что он `active`

## 2. Наблюдатель за состоянием диктовки

- [x] 2.1 `dot_local/bin/handmade-scripts/executable_voxtype-mute-others`:
  чтение потока `voxtype status --follow`, выключение
  `@DEFAULT_AUDIO_SINK@` на состояниях, отличных от `idle` и `stopped`,
  возврат прежнего состояния, обработчик сигнала, без таймеров и пауз
- [x] 2.2 Признак «звук выключили мы» — файл-метка
  `$XDG_RUNTIME_DIR/voxtype-mute-others.muted`, чтобы новый экземпляр
  довёл до конца возврат звука за экземпляром, снятым сигналом KILL
- [x] 2.3 `dot_config/systemd/user/voxtype-mute-others.service`: `BindsTo`
  и `After` на `voxtype.service`, `PartOf` на `graphical-session.target`,
  `WantedBy=voxtype.service`, `Restart=on-failure`, `RestartSec=5`,
  `KillMode=mixed`
- [x] 2.4 `chezmoi apply`, `systemctl --user daemon-reload`,
  `systemctl --user enable --now voxtype-mute-others.service`, проверить
  `is-active` и журнал

## 3. Проверки без диктовки

- [x] 3.1 Обычная диктовка: `recording` и `transcribing` дают `[MUTED]`,
  `idle` снимает выключение
- [x] 3.2 Отмена записи: `recording` → `idle` без `transcribing` возвращает
  звук
- [x] 3.3 Звук выключен пользователем заранее: после `recording` → `idle`
  звук остаётся выключенным, метка не появляется
- [x] 3.4 Остановка `voxtype-mute-others.service` посреди записи возвращает
  звук (5 прогонов без отказов)
- [x] 3.5 Остановка `voxtype.service` посреди записи останавливает
  наблюдателя и возвращает звук (5 прогонов без отказов; с `KillMode` по
  умолчанию было 2 отказа из 4 — см. D4)
- [x] 3.6 Снятие наблюдателя сигналом KILL посреди записи: после
  перезапуска юнита звук возвращён, метка удалена
- [x] 3.7 Перезапуск `voxtype.service` не обрывает поток
  `voxtype status --follow`: он выдаёт `idle`, `stopped`, `idle`

## 4. Документация

- [x] 4.1 `docs/media-and-portals.md`: раздел «voxtype» дополнен описанием
  двух слоёв тишины и способов проверки
- [x] 4.2 `AGENTS.md`: фраза о новом юните и ключе `pause_media` в разделе
  «Сессия Hyprland»

## 5. Проверка живой диктовкой (пользователь)

- [ ] 5.1 Продиктовать фразу при играющем видео в браузере и при звуке
  уведомления: плеер встаёт на паузу и возобновляется после распознавания,
  остальной звук выключен на время записи и распознавания и возвращается
  после
