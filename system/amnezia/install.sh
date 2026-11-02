#!/usr/bin/env bash
# Установка туннеля AmneziaWG с маршрутизацией по адресу назначения
# (устройство — docs/amnezia-split-tunnel.md, решение — docs/decisions/0009).
#
# Действия:
#   files   разложить сценарии в /usr/local/sbin, списки и шаблон
#           в /etc/amnezia, настройку NetworkManager в conf.d, правило
#           /etc/sudoers.d/amn-switch и собрать
#           /etc/amnezia/amneziawg/amn0.conf из хранилища AmneziaVPN
#   switch  перейти с приложения AmneziaVPN на awg-quick@amn0 — то же, что
#           sudo /usr/local/sbin/amn-switch (запускается пользователем
#           из терминала, пароль не спрашивается)
#   revert  вернуть приложение: выключить awg-quick@amn0.service, вернуть
#           соединению axata маршрут по умолчанию, включить AmneziaVPN.service
#   status  состояние служб, правила, таблица 100, размер набора zones
#
# Права root сценарий получает сам через sudo -A (окно Quickshell askpass):
#   system/amnezia/install.sh files
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/$(basename "$0")"
askpass=${SUDO_ASKPASS:-$HOME/.local/bin/handmade-scripts/sudo-askpass}
action=${1:-}

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    if [ ! -x "$askpass" ]; then
        echo "не найдена обёртка askpass: $askpass" >&2
        exit 1
    fi
    exec env SUDO_ASKPASS="$askpass" sudo -A \
        -p "Туннель AmneziaWG: действие $action сценария system/amnezia/install.sh" \
        -- "$script" "$@"
}

case "$action" in
files)
    need_root "$@"
    install -d -m 0755 /etc/amnezia
    install -d -m 0700 /etc/amnezia/amneziawg
    for f in amn-export-config amn-zones-update amn-route amn-switch; do
        install -m 0755 -o root -g root "$here/$f" "/usr/local/sbin/$f"
    done
    for f in amn.nft amn0.conf.template countries.txt domains.txt bypass.txt; do
        install -m 0644 -o root -g root "$here/$f" "/etc/amnezia/$f"
    done
    install -D -m 0644 -o root -g root \
        "$here/../NetworkManager/conf.d/90-amn0-unmanaged.conf" \
        /etc/NetworkManager/conf.d/90-amn0-unmanaged.conf
    nmcli general reload conf
    sudoers="$here/../sudo/sudoers.d/amn-switch"
    visudo -c -f "$sudoers"
    install -m 0440 -o root -g root "$sudoers" /etc/sudoers.d/amn-switch
    /usr/local/sbin/amn-export-config
    ;;
switch)
    # Без need_root: правило sudoers.d/amn-switch пускает только сам сценарий.
    [ "$(id -u)" -eq 0 ] && exec /usr/local/sbin/amn-switch "${@:2}"
    exec sudo -n /usr/local/sbin/amn-switch "${@:2}"
    ;;
revert)
    need_root "$@"
    systemctl disable --now awg-quick@amn0.service
    nmcli connection modify axata ipv4.never-default no
    # Изменение профиля действует на активное соединение после переподъёма.
    if nmcli -t -f NAME connection show --active | grep -qxF axata; then
        nmcli connection up axata
    fi
    systemctl enable --now AmneziaVPN.service
    ;;
status)
    need_root "$@"
    systemctl is-enabled AmneziaVPN.service awg-quick@amn0.service || true
    systemctl is-active AmneziaVPN.service awg-quick@amn0.service || true
    ip -4 rule
    ip -4 route show table 100
    for field in latest-handshakes transfer; do
        awg show amn0 "$field" 2>/dev/null | sed "s/^[^[:space:]]*/$field/" || true
    done
    echo "элементов zones: $(/usr/local/sbin/amn-zones-update --count 2>/dev/null || echo нет таблицы)"
    ;;
*)
    # Справка — шапка файла: комментарии после строки #!, до первой иной.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$script"
    exit 2
    ;;
esac
