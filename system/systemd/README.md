# Настройки systemd вне `$HOME`

`coredump.conf.d/50-size-limit.conf` — предел размера дампа памяти 4 ГиБ
для всех программ (`ProcessSizeMax`, `ExternalSizeMax`), причина — в
комментарии файла. chezmoi каталог `system/` не применяет, файл ставится
вручную с правами root:

```bash
sudo -A -p 'Установка предела размера дампов памяти systemd-coredump' \
    install -D -m 0644 -o root -g root \
    system/systemd/coredump.conf.d/50-size-limit.conf \
    /etc/systemd/coredump.conf.d/50-size-limit.conf
```

Перезапуск не нужен: systemd-coredump читает конфиг при каждом запуске.
