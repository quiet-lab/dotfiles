#!/usr/bin/env sh
#
# These things are run when an Openbox X Session is started.
# You may place a similar script in "${HOME}/.config/openbox/autostart" to run user-specific things.
#
# https://github.com/owl4ce/dotfiles
#
# shellcheck disable=SC3044,SC2091,SC2086
# ---

exec >/dev/null 2>&1

{ pidof -s pulseaudio -q || pulseaudio --start --log-target=syslog; } &

# Уведомления (~/.config/dunst/dunstrc) и обои, сохранённые nitrogen
# (~/.config/nitrogen/bg-saved.cfg). Раньше их запускал механизм режимов
# joyful-desktop, теперь он удалён.
dunst &
nitrogen --restore &

# Программы трея XEmbed: через xembedsniproxy попадают в трей eww.
{ pidof -s nm-applet -q || nm-applet; } &
{ pidof -s pasystray -q || pasystray; } &

picom -b
if [ -x "$(command -v lxpolkit)" ]; then
  lxpolkit &
else
  $(find /usr/lib /usr/lib64 /usr/libexec /usr/local/lib -type f -iname 'polkit-gnome-authentication-agent-*' 2>/dev/null | sed 1q) &
fi

Handy.AppImage &
wezterm-gui &
firefox &
xset s off &
xset -dpms &
xset s noblank &
# Раскладки и переключение: запасной setxkbmap (если xkbcomp не сработает),
# затем пользовательская карта XKB с Alt+E/Alt+R и Win+Пробел.
setxkbmap -layout "us,ru" -option grp:win_space_toggle
xkbcomp /home/mne/.config/X11/xkb_custom $DISPLAY
~/.local/bin/kb_listener.sh &

# Any additions should be added below.

# Менеджер буфера обмена: clipcatd сам уходит в фон (daemonize в clipcatd.toml).
{ [ -x "$(command -v clipcatd)" ] && { pgrep -x clipcatd >/dev/null || clipcatd; }; } &

# Дашборд eww, затем мост XEmbed → StatusNotifier: иконки старого протокола
# (nm-applet и т. п.) попадают в трей eww. Мост стартует после eww, потому что
# ему нужен StatusNotifierWatcher, который регистрирует eww.
#
# `eww daemon` возвращает управление сразу после fork, а сокет поднимает позже,
# уже после инициализации GTK. Если `open-many` не дождётся сокета, он запустит
# второй демон, поэтому перед ним ждём ответа `eww ping` (до 20 с), а сам
# `open-many` вызываем с --no-daemonize: тогда он не сможет породить демон.
{
  if [ -x "$(command -v eww)" ]; then
    pidof -s eww -q || eww daemon
    eww_wait=0
    until eww ping >/dev/null 2>&1 || [ "$eww_wait" -ge 100 ]; do
      eww_wait=$((eww_wait + 1))
      sleep 0.2
    done
    eww --no-daemonize open-many tile-pwr-lock tile-pwr-logout tile-pwr-restart tile-pwr-reboot tile-pwr-off tile-clock tile-weather tile-cpu tile-ram tile-gpu tile-network tile-disks tile-favorites tile-ws1 tile-ws2 tile-ws3 tile-ws4 tile-ws5 tile-ws6 tile-ws7 tile-ws8 tile-launcher tile-tray tile-lang \
      && [ -x "$(command -v xembedsniproxy)" ] && { pgrep -x xembedsniproxy >/dev/null || xembedsniproxy; }
  fi
} &
