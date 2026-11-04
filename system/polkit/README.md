# /etc/polkit-1/rules.d/50-mne-admin.rules

Правило polkit: пользователю `mne` (только ему, не группе) без пароля
открыты действия служб `org.freedesktop.resolve1.*`, `systemd1.*`,
`login1.*`, `machine1.*`, `udisks2.*`, `hostname1.*`, `timedate1.*`,
`locale1.*` (результат `polkit.Result.YES`). Нужно агенту: у него нет
терминала, а окно агента polkit «Authentication Required» отвлекает
(например, `resolvectl statistics`). Правило согласовано с разделом
«Повышение привилегий» `~/.claude/CLAUDE.md`.

Пакет polkit кладёт свои правила в `/usr/share/polkit-1/rules.d`,
пользовательские лежат в `/etc/polkit-1/rules.d`.

## Установка

```bash
system/polkit/install.sh
journalctl -u polkit -n 5
```

polkitd перечитывает каталог сам, службы не перезапускаются. Ошибка
JavaScript в правиле выключает весь файл, поэтому журнал проверяется
после установки.

## Проверка

```bash
resolvectl statistics
systemctl reset-failed
loginctl list-sessions
pkcheck --action-id org.freedesktop.resolve1.dump-statistics --process $$; echo rc=$?
```

Всё выполняется без окна и пароля, `pkcheck` возвращает 0.

## Снятие

```bash
sudo -A -p 'снять правило polkit пользователя станции' rm /etc/polkit-1/rules.d/50-mne-admin.rules
```
