#!/usr/bin/env bash
# Автозапуск туннелей станции при загрузке системы, до экрана входа
# (docs/amnezia-split-tunnel.md, раздел «Автозапуск туннелей»; изменение
# OpenSpec tunnel-tray-autostart).
#
# Действия:
#   files   положить юниты axata-vpn.service и tunnels-before-login.service
#           в /etc/systemd/system и включить их (соединение axata
#           не переподключается: юнит запускается сейчас, только если
#           axata не активно)
#   status  состояние юнитов и соединения axata
#
# Права root сценарий получает сам через sudo -A (окно Quickshell askpass):
#   system/tunnels/install.sh files
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/$(basename "$0")"
askpass=${SUDO_ASKPASS:-$HOME/.local/bin/handmade-scripts/sudo-askpass}
action=${1:-}
units=(axata-vpn.service tunnels-before-login.service)

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    if [ ! -x "$askpass" ]; then
        echo "не найдена обёртка askpass: $askpass" >&2
        exit 1
    fi
    exec env SUDO_ASKPASS="$askpass" sudo -A \
        -p "Туннели: действие $action сценария system/tunnels/install.sh" \
        -- "$script" "$@"
}

case "$action" in
files)
    need_root "$@"
    for u in "${units[@]}"; do
        install -m 0644 -o root -g root "$here/$u" "/etc/systemd/system/$u"
    done
    systemctl daemon-reload
    systemctl enable "${units[@]}"
    # Условие ExecCondition юнита пропускает запуск, если axata уже активно.
    systemctl start axata-vpn.service
    ;;
status)
    systemctl is-enabled "${units[@]}" || true
    systemctl is-active "${units[@]}" || true
    nmcli -f connection.autoconnect,connection.secondaries connection show id axata
    nmcli -t -f NAME,DEVICE connection show --active
    ;;
*)
    # Справка — шапка файла: комментарии после строки #!, до первой иной.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$script"
    exit 2
    ;;
esac
