#!/usr/bin/env bash
# Обновление herdr из AUR при загрузке системы, до экрана входа (спецификация
# hyprland-autostart, требование «Обновление herdr при загрузке»; README рядом).
#
# Действия:
#   files   положить сценарий herdr-update в /usr/local/sbin и юнит
#           herdr-update.service в /etc/systemd/system и включить юнит
#           (сейчас он не запускается: первая отработка — при загрузке)
#   status  состояние юнита и последний запуск в журнале
#
# Права root сценарий получает сам через sudo -A (окно Quickshell askpass):
#   system/herdr-update/install.sh files
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/$(basename "$0")"
askpass=${SUDO_ASKPASS:-$HOME/.local/bin/handmade-scripts/sudo-askpass}
action=${1:-}
unit=herdr-update.service

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    if [ ! -x "$askpass" ]; then
        echo "не найдена обёртка askpass: $askpass" >&2
        exit 1
    fi
    exec env SUDO_ASKPASS="$askpass" sudo -A \
        -p "Обновление herdr при загрузке: действие $action сценария system/herdr-update/install.sh" \
        -- "$script" "$@"
}

case "$action" in
files)
    need_root "$@"
    install -m 0755 -o root -g root "$here/herdr-update" /usr/local/sbin/herdr-update
    install -m 0644 -o root -g root "$here/$unit" "/etc/systemd/system/$unit"
    systemctl daemon-reload
    systemctl enable "$unit"
    ;;
status)
    systemctl is-enabled "$unit" || true
    systemctl is-active "$unit" || true
    journalctl -b -u "$unit" --no-pager -n 20 || true
    ;;
*)
    # Справка — шапка файла: комментарии после строки #!, до первой иной.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$script"
    exit 2
    ;;
esac
