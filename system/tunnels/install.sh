#!/usr/bin/env bash
# Автозапуск туннелей станции при загрузке системы, до экрана входа, и
# профили сети (docs/amnezia-split-tunnel.md, разделы «Автозапуск туннелей»
# и «Профили сети»; изменения OpenSpec tunnel-tray-autostart
# и tunnel-backup-profile).
#
# Действия:
#   files    положить юниты axata-vpn.service и tunnels-before-login.service
#            в /etc/systemd/system и включить их, drop-in awg-quick@amn0
#            (условие запуска по профилю сети), сценарий net-profile
#            в /usr/local/sbin (соединение не переподключается: юнит
#            запускается сейчас, только если ни axata, ни axata-full
#            не активно)
#   profile  создать соединение axata-full — копию axata без
#            ipv4.never-default (запасной профиль); повторный запуск
#            пересоздаёт его из axata, пока оно не активно
#   status   состояние юнитов, профиля сети и соединений axata, axata-full
#
# Права root сценарий получает сам через sudo -A (окно Quickshell askpass):
#   system/tunnels/install.sh files
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/$(basename "$0")"
askpass=${SUDO_ASKPASS:-$HOME/.local/bin/handmade-scripts/sudo-askpass}
action=${1:-}
units=(axata-vpn.service tunnels-before-login.service)
dropin=awg-quick@amn0.service.d/10-profile.conf

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

con_active() { nmcli -t -f NAME connection show --active | grep -qxF "$1"; }
con_exists() { nmcli -t -f NAME connection show | grep -qxF "$1"; }

case "$action" in
files)
    need_root "$@"
    for u in "${units[@]}"; do
        install -m 0644 -o root -g root "$here/$u" "/etc/systemd/system/$u"
    done
    install -D -m 0644 -o root -g root "$here/$dropin" "/etc/systemd/system/$dropin"
    install -m 0755 -o root -g root "$here/net-profile" /usr/local/sbin/net-profile
    systemctl daemon-reload
    systemctl enable "${units[@]}"
    # Условие ExecCondition юнита пропускает запуск, если axata или
    # axata-full уже активно.
    systemctl start axata-vpn.service
    ;;
profile)
    need_root "$@"
    if con_active axata-full; then
        echo "axata-full активно — сначала net-profile main, затем повторить" >&2
        exit 1
    fi
    if con_exists axata-full; then
        nmcli connection delete id axata-full
    fi
    # clone копирует и секреты (пароль хранится в профиле, password-flags = 0);
    # маршрут 10.0.0.0/8 остаётся и рядом с полным туннелем безвреден.
    nmcli connection clone id axata axata-full
    nmcli connection modify id axata-full ipv4.never-default no \
        connection.autoconnect no connection.secondaries ''
    if [ -z "$(nmcli -s -g vpn.secrets connection show id axata-full)" ]; then
        echo "у axata-full нет секретов (пароль не скопирован) — соединение удалено" >&2
        nmcli connection delete id axata-full
        exit 1
    fi
    nmcli -f connection.id,connection.uuid,ipv4.never-default,connection.autoconnect \
        connection show id axata-full
    ;;
status)
    systemctl is-enabled "${units[@]}" || true
    systemctl is-active "${units[@]}" || true
    echo "профиль сети: $(cat /etc/amnezia/profile 2>/dev/null || echo 'нет файла (основной)')"
    for c in axata axata-full; do
        if con_exists "$c"; then
            nmcli -f connection.id,connection.autoconnect,connection.secondaries,ipv4.never-default \
                connection show id "$c"
        else
            echo "соединения $c нет"
        fi
    done
    if con_exists axata-full; then
        if [ "$(nmcli -g vpn.data connection show id axata)" = "$(nmcli -g vpn.data connection show id axata-full)" ]; then
            echo "vpn.data axata и axata-full совпадают"
        else
            echo "vpn.data axata и axata-full РАСХОДЯТСЯ — пересоздать: system/tunnels/install.sh profile"
        fi
    fi
    nmcli -t -f NAME,DEVICE connection show --active
    ;;
*)
    # Справка — шапка файла: комментарии после строки #!, до первой иной.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$script"
    exit 2
    ;;
esac
