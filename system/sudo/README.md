# /etc/sudo.conf

`sudo.conf` — копия системного `/etc/sudo.conf` (пакет sudo) с одной добавленной
строкой:

```
Path askpass /home/mne/.local/bin/handmade-scripts/sudo-askpass
```

С ней `sudo -A` запускает окно ввода пароля Quickshell (спецификация
qs-askpass) и без переменной `SUDO_ASKPASS`. Переменная задана и в окружении
сессии (`hyprland.lua`, `~/.profile`); если она есть, sudo берёт её, а не строку
из `sudo.conf`.

chezmoi каталог `system/` не применяет, файл ставится вручную с правами root:

```bash
sudo -A -p 'Установка /etc/sudo.conf со строкой Path askpass' \
    install -m 0644 -o root -g root system/sudo/sudo.conf /etc/sudo.conf
```

Проверка — окно должно появиться и при пустой переменной:

```bash
sudo -k
env -u SUDO_ASKPASS sudo -A -p 'Проверка окна askpass' true
```

Файл помечен в пакете sudo как файл настройки, поэтому при обновлении пакета
pacman не перезаписывает его, а кладёт рядом `/etc/sudo.conf.pacnew`. Новую
версию из `.pacnew` нужно сверить с этой копией, перенести строку `Path askpass`
и обновить копию в репозитории.
