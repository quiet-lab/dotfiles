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
. "${HOME}/.joyfuld"

# https://gnu.org/software/bash/manual/html_node/The-Shopt-Builtin.html#:~:text=expand_aliases
[ -z "$BASH" ] || shopt -s expand_aliases

#{ [ "$(joyd_launch_apps -g terminal)" = 'urxvtc' ] && urxvtd -f -q; } &

{ pidof -s pulseaudio -q || pulseaudio --start --log-target=syslog; } &

joyd_toggle_mode apply
joyd_tray_programs exec

picom -b
if [ -x "$(command -v lxpolkit)" ]; then
  lxpolkit &
else
  $(find ${LIBS_PATH} -type f -iname 'polkit-gnome-authentication-agent-*' | sed 1q) &
fi

{ [ -x "$(command -v xss-lock)" ] && xss-lock -q -l "${JOYD_DIR}/xss-lock-tsl.sh"; } &
Handy.AppImage &
wezterm-gui &
firefox &
xset s off &
xset -dpms &
xset s noblank &
joyd_mpd_notifier
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
{ [ -x "$(command -v eww)" ] && { pidof -s eww -q || eww daemon; } && eww open-many tile-pwr-lock tile-pwr-logout tile-pwr-restart tile-pwr-reboot tile-pwr-off tile-clock tile-weather tile-cpu tile-ram tile-gpu tile-volume tile-network tile-disks tile-favorites tile-ws1 tile-ws2 tile-ws3 tile-ws4 tile-ws5 tile-ws6 tile-ws7 tile-ws8 tile-launcher tile-tray tile-lang && [ -x "$(command -v xembedsniproxy)" ] && { pgrep -x xembedsniproxy >/dev/null || xembedsniproxy; }; } &
