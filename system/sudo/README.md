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

# /etc/sudoers.d/mne-read-dirs

`sudoers.d/mne-read-dirs` — правило, по которому пользователь `mne` без
пароля выполняет с правами root команды чтения каталогов и файлов: `du`, `ls`,
`stat`, `tree`, `find`, `cat`, `btrfs filesystem du`, `btrfs filesystem usage`,
`btrfs subvolume list`, `btrfs subvolume show`. Нужно агенту, чтобы считать
размеры, искать и читать файлы с чужими правами (например, прежний корень
Ubuntu в `~/ubuntu`), не спрашивая пароль на каждую команду. Аргументы `find`
правило не ограничивает, поэтому `find -delete` и `find -exec` тоже проходят
без пароля. Команды записи (`rm`, `cp`, `mv`, `install`, `tee`) в правило
не входят и идут через `sudo -A -p`.

Установка:

```bash
visudo -c -f system/sudo/sudoers.d/mne-read-dirs
sudo -A -p 'Установка правила sudoers для чтения каталогов' \
    install -m 0440 -o root -g root system/sudo/sudoers.d/mne-read-dirs /etc/sudoers.d/mne-read-dirs
```

Проверка: `sudo -n du -xsh /root` выполняется без окна пароля.

Три неверных ввода пароля подряд (в том числе пустых, если окно показали
с обрезанной подсказкой и пароль ввели не туда) включают блокировку
pam_faillock на 10 минут: sudo отвечает «Попробуйте ещё раз» и на верный
пароль. Состояние — `faillock --user mne`, сброс раньше срока —
`faillock --user mne --reset` с правами root.

# /etc/sudoers.d/mne-prlimit

`sudoers.d/mne-prlimit` — правило, по которому пользователь `mne` без
пароля выполняет `prlimit` с правами root: замеры служб на io_uring снимают
предел заблокированной памяти (`RLIMIT_MEMLOCK`) уже запущенному процессу,
а поднять предел выше жёсткого потолка может только root. Аргументы правило
не ограничивает.

Установка:

```bash
visudo -c -f system/sudo/sudoers.d/mne-prlimit
sudo -A -p 'Установка правила sudoers для prlimit' \
    install -m 0440 -o root -g root system/sudo/sudoers.d/mne-prlimit /etc/sudoers.d/mne-prlimit
```

Проверка: `sudo -n prlimit --pid $$ --memlock` печатает пределы без окна пароля.
