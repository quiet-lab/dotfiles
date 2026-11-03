# Обновление herdr при загрузке (`/etc/systemd/system`)

Поведение — спецификация `hyprland-autostart`, требование «Обновление herdr
при загрузке»; выбор пакета AUR вместо `herdr update` и условие пересмотра —
[`design.md`](../../openspec/changes/archive/2026-11-03-herdr-prestart/design.md)
изменения OpenSpec herdr-prestart.

| Файл | Куда ставится | Что это |
|---|---|---|
| `herdr-update` | `/usr/local/sbin` | сравнивает версию `herdr-bin` в AUR с установленной, при новой собирает пакет `makepkg` от пользователя `mne` и ставит `pacman -U` |
| `herdr-update.service` | `/etc/systemd/system`, включается в `greetd.service.wants` | запуск сценария после сети и туннеля `amn0`; экран входа ждёт его не дольше 240 с от начала загрузки |
| `install.sh` | не ставится | установка и состояние |

```bash
system/herdr-update/install.sh files    # права root спрашивает окно askpass
system/herdr-update/install.sh status
```

Запросы к AUR сценарий привязывает к туннелю `amn0` (`curl --interface amn0`):
без привязки рукопожатие TLS с AUR обрывается
([`amn0-tcp-mss.md`](../../docs/open-questions/amn0-tcp-mss.md)). Пользователь сборки
задаёт переменная `HERDR_UPDATE_USER` (по умолчанию `mne`). Откат —
`sudo -A -p 'Откат обновления herdr при загрузке' systemctl disable herdr-update.service`.
