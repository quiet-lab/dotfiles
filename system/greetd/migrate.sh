#!/usr/bin/env bash
# Переезд с LightDM на greetd + tuigreet (изменение OpenSpec greetd-login).
# Запуск без терминала, пароль sudo спрашивает графический askpass:
#   SUDO_ASKPASS=~/.local/bin/handmade-scripts/sudo-askpass sudo -A system/greetd/migrate.sh prepare
#   SUDO_ASKPASS=~/.local/bin/handmade-scripts/sudo-askpass sudo -A system/greetd/migrate.sh cleanup
# Этап prepare — до перезагрузки, cleanup — после удачного входа через tuigreet.
# Этап prepare не трогает работающий LightDM: службы только переключаются,
# сам LightDM удаляется на этапе cleanup, когда новый вход проверен.
# Терминала у сценария нет, поэтому pacman работает с --noconfirm, а список
# осиротевших пакетов только печатается.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
login_user=mne

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "нужны права root: sudo $0 $*" >&2
        exit 1
    fi
}

prepare() {
    need_root prepare
    echo "== пакеты: greetd, tuigreet; удаление sxhkd и dmenu =="
    pacman -S --needed --noconfirm greetd greetd-tuigreet
    pacman -Rns --noconfirm sxhkd dmenu || true

    echo "== /etc/greetd/config.toml =="
    install -d -m 0755 /etc/greetd
    if [ -f /etc/greetd/config.toml ] && ! cmp -s "$here/config.toml" /etc/greetd/config.toml; then
        cp -a /etc/greetd/config.toml "/etc/greetd/config.toml.bak-$(date +%F)"
    fi
    install -m 0644 "$here/config.toml" /etc/greetd/config.toml

    echo "== кэш tuigreet для запоминания пользователя =="
    install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet

    echo "== службы: lightdm выключается, greetd включается (запуск после перезагрузки) =="
    systemctl disable lightdm.service
    systemctl enable greetd.service
    echo "готово: перезагрузите систему, войдите через tuigreet, затем выполните cleanup"
}

cleanup() {
    need_root cleanup
    if ! systemctl is-active --quiet greetd.service; then
        echo "greetd не запущен, сначала перезагрузитесь и войдите через tuigreet" >&2
        exit 1
    fi
    echo "== удаление LightDM, slick-greeter и осиротевших зависимостей (xorg-server и другие) =="
    pacman -Rns --noconfirm lightdm-slick-greeter lightdm
    orphans=$(pacman -Qdtq || true)
    if [ -n "$orphans" ]; then
        echo "остались осиротевшие пакеты, удалите их отдельно, если не нужны:"
        echo "$orphans"
    fi
    echo "== файлы пользователя, оставшиеся от LightDM и X11-сессии =="
    home=$(getent passwd "$login_user" | cut -d: -f6)
    for f in "$home/.dmrc" "$home/.xprofile" "$home/.xsession-errors" "$home/.xsession-errors.old"; do
        [ -e "$f" ] && rm -v "$f"
    done
    echo "готово"
}

case "${1:-}" in
    prepare) prepare ;;
    cleanup) cleanup ;;
    *) echo "использование: $0 prepare|cleanup" >&2; exit 2 ;;
esac
