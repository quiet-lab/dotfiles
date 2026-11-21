#!/usr/bin/env bash
# Проверка логики net-profile на подставных командах, без root и без
# изменения системы (изменение OpenSpec tunnel-backup-profile, задача 2.6):
#
#   system/tunnels/tests/net-profile.sh
#
# Боевой сценарий PATH и пути задаёт сам и из окружения их не берёт. Проверка
# поэтому собирает копию сценария во временном каталоге: строка PATH= и блок
# путей заменяются путями к заглушкам и файлам состояния, остальной текст
# не меняется. Заглушки nmcli, systemctl, ip, nft, resolvectl, curl, pgrep, id
# хранят состояние станции файлами в каталоге $state. Ожиданий по сроку нет:
# одновременный вызов проверяется замком, который держит сама проверка.
# Условия expect записаны в одинарных кавычках и вычисляются eval после
# вызова сценария: переменные out и code читаются в них.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
src="$here/../net-profile"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stub="$work/bin"
state="$work/state"
sys="$work/sys"
mkdir -p "$stub" "$state" "$sys" "$work/etc/amneziawg"
script="$work/net-profile"

# --- Копия сценария с путями проверки ---
awk -v stub="$stub" -v w="$work" -v sys="$sys" '
    /^PATH=/ { print "PATH=" stub ":/usr/bin"; next }
    /^profile_file=/ { print "profile_file=" w "/etc/profile"; next }
    /^amn_conf=/ { print "amn_conf=" w "/etc/amneziawg/amn0.conf"; next }
    /^log=/ { print "log=" w "/net-profile.log"; next }
    /^lock=/ { print "lock=" w "/net-profile.lock"; next }
    /^sysnet=/ { print "sysnet=" sys; next }
    { print }
' "$src" >"$script"
chmod +x "$script"
# Заменены ровно шесть строк, остальное совпадает с боевым сценарием.
changed=$(diff "$src" "$script" | grep -c '^>')
if [ "$changed" -ne 6 ]; then
    echo "копия сценария: заменено строк $changed, ожидалось 6" >&2
    exit 1
fi

# --- Заглушки ---
# Состояние: connections — все соединения NetworkManager, active — активные
# по строке; amn —
# active или inactive; calls — журнал вызовов, меняющих состояние;
# fail_up_<имя>, amnezia_down, anthropic_down — неисправности.
cat >"$stub/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$stub/pgrep" <<EOF
#!/bin/sh
cat "$state/openvpn_pids" 2>/dev/null
EOF
cat >"$stub/nmcli" <<EOF
#!/usr/bin/env bash
state="$state"; sys="$sys"
EOF
cat >>"$stub/nmcli" <<'EOF'
args="$*"
tun_up() { mkdir -p "$sys/tun0/statistics"; [ -e "$sys/tun0/statistics/rx_bytes" ] || echo 1000 >"$sys/tun0/statistics/rx_bytes"; }
case "$args" in
"-t -f NAME connection show --active") cat "$state/active" ;;
"-t -f NAME connection show") cat "$state/connections" ;;
"-t -f NAME,DEVICE connection show --active") sed 's/$/:enp43s0/' "$state/active" ;;
"-g vpn.data connection show id "*) echo 'ca = /x/ca.crt, remote = 213.184.245.91\:1194, username = u' ;;
"connection down id "*)
    name=${args#connection down id }
    echo "down $name" >>"$state/calls"
    grep -qxF "$name" "$state/active" || exit 10
    grep -vxF "$name" "$state/active" >"$state/active.new"; mv "$state/active.new" "$state/active"
    grep -qxE 'axata|axata-full' "$state/active" || rm -rf "$sys/tun0"
    ;;
"--wait 60 connection up id "*)
    name=${args#--wait 60 connection up id }
    echo "up $name" >>"$state/calls"
    [ -e "$state/fail_up_$name" ] && { echo "Ошибка: активация не удалась" >&2; exit 4; }
    grep -vxF "$name" "$state/active" >"$state/active.new"; mv "$state/active.new" "$state/active"
    echo "$name" >>"$state/active"
    tun_up
    ;;
*) echo "nmcli-заглушка: неизвестный вызов: $args" >&2; exit 99 ;;
esac
EOF
cat >"$stub/systemctl" <<EOF
#!/usr/bin/env bash
state="$state"; sys="$sys"; profile="$work/etc/profile"
EOF
cat >>"$stub/systemctl" <<'EOF'
case "$1" in
is-active)
    [ "$2" = --quiet ] && { [ "$(cat "$state/amn")" = active ]; exit; }
    cat "$state/amn"; [ "$(cat "$state/amn")" = active ] ;;
stop)
    echo "stop $2" >>"$state/calls"
    echo inactive >"$state/amn"; rm -rf "$sys/amn0" ;;
start | restart)
    echo "$1 $2" >>"$state/calls"
    # Условие запуска 10-profile.conf: при backup юнит пропускается.
    grep -sqx backup "$profile" && { echo inactive >"$state/amn"; exit 0; }
    [ -e "$state/fail_amn" ] && { echo failed >"$state/amn"; exit 1; }
    echo active >"$state/amn"; mkdir -p "$sys/amn0/statistics"; echo 500 >"$sys/amn0/statistics/rx_bytes" ;;
*) echo "systemctl-заглушка: неизвестный вызов: $*" >&2; exit 99 ;;
esac
EOF
cat >"$stub/ip" <<EOF
#!/usr/bin/env bash
state="$state"; sys="$sys"
EOF
cat >>"$stub/ip" <<'EOF'
full() { grep -qx axata-full "$state/active"; }
split() { grep -qx axata "$state/active"; }
amn() { [ "$(cat "$state/amn")" = active ]; }
case "$*" in
"-4 route get 213.184.245.91") echo "213.184.245.91 via 192.168.1.1 dev enp43s0 src 192.168.1.11" ;;
"-4 route get "*" mark 0x1") if amn; then echo "$4 dev amn0 table 100 mark 0x1"; else echo "$4 via 192.168.1.1 dev enp43s0"; fi ;;
"-4 route get "*) if full; then echo "$4 via 10.200.5.254 dev tun0"; else echo "$4 via 192.168.1.1 dev enp43s0"; fi ;;
"-4 rule show pref 5100") amn && echo "5100:	from all fwmark 0x1 lookup 100" ;;
"-4 route show exact 10.0.0.0/8") { full || split; } && echo "10.0.0.0/8 via 10.200.5.254 dev tun0 proto static" ;;
"-4 route show default") full && echo "default via 10.200.5.254 dev tun0"; echo "default via 192.168.1.1 dev enp43s0" ;;
"-4 route") echo "default via 192.168.1.1 dev enp43s0" ;;
"-4 -o addr show dev tun0") [ -e "$sys/tun0" ] && echo "7: tun0    inet 10.200.4.175/23 scope global tun0" ;;
*) echo "ip-заглушка: неизвестный вызов: $*" >&2; exit 99 ;;
esac
EOF
cat >"$stub/nft" <<EOF
#!/usr/bin/env bash
state="$state"
EOF
cat >>"$stub/nft" <<'EOF'
case "$*" in
"list table inet amn") [ "$(cat "$state/amn")" = active ] ;;
"get element inet amn "*) exit 1 ;;
*) echo "nft-заглушка: неизвестный вызов: $*" >&2; exit 99 ;;
esac
EOF
cat >"$stub/resolvectl" <<EOF
#!/usr/bin/env bash
state="$state"
EOF
cat >>"$stub/resolvectl" <<'EOF'
full() { grep -qx axata-full "$state/active"; }
case "$*" in
"dns tun0") full && echo "Link 7 (tun0): 10.200.115.1 10.200.115.2" || echo "Link 7 (tun0):" ;;
"default-route tun0") if full && [ ! -e "$state/no_default_route" ]; then echo "Link 7 (tun0): yes"; else echo "Link 7 (tun0): no"; fi ;;
"domain enp43s0") echo "Link 2 (enp43s0): ~ru ~by ~su ~xn--p1ai bbrouter" ;;
*) echo "resolvectl-заглушка: неизвестный вызов: $*" >&2; exit 99 ;;
esac
EOF
cat >"$stub/curl" <<EOF
#!/usr/bin/env bash
state="$state"; sys="$sys"
EOF
cat >>"$stub/curl" <<'EOF'
url=${*: -1}
bump() { f="$sys/$1/statistics/rx_bytes"; echo $(($(cat "$f") + 4000)) >"$f"; }
case "$url" in
https://api.anthropic.com/)
    [ -e "$state/anthropic_down" ] && { echo "curl: (28) Connection timed out"; exit 28; }
    if [ "$(cat "$state/amn")" = active ]; then
        [ -e "$state/amnezia_down" ] && { echo "curl: (28) Connection timed out"; exit 28; }
        bump amn0
    elif grep -qx axata-full "$state/active"; then
        bump tun0
    fi
    printf '160.79.104.10 404' ;;
https://ya.ru) exit 0 ;;
*) echo "curl-заглушка: неизвестный адрес: $url" >&2; exit 99 ;;
esac
EOF
chmod +x "$stub"/*

# --- Состояния станции ---
reset() {
    rm -rf "${state:?}"/* "${sys:?}"/* "$work/etc/profile" "$work/net-profile.log"
    : >"$state/calls"
    printf '%s\n' "Проводное подключение 2" axata axata-full >"$state/connections"
    : >"$work/etc/amneziawg/amn0.conf"
}
# Основной профиль: amn0 и axata подняты.
state_main() {
    reset
    echo main >"$work/etc/profile"
    echo active >"$state/amn"
    mkdir -p "$sys/amn0/statistics" "$sys/tun0/statistics"
    echo 500 >"$sys/amn0/statistics/rx_bytes"
    echo 1000 >"$sys/tun0/statistics/rx_bytes"
    printf '%s\n' "Проводное подключение 2" axata >"$state/active"
}
# Запасной профиль: amn0 остановлен, axata-full поднято.
state_backup() {
    reset
    echo backup >"$work/etc/profile"
    echo inactive >"$state/amn"
    mkdir -p "$sys/tun0/statistics"
    echo 1000 >"$sys/tun0/statistics/rx_bytes"
    printf '%s\n' "Проводное подключение 2" axata-full >"$state/active"
}

failures=0
out=""
code=0
run() {
    out=$("$script" "$@" 2>"$work/stderr")
    code=$?
}
expect() {
    if eval "$2"; then
        echo "  да: $1"
    else
        echo "  НЕТ: $1"
        failures=$((failures + 1))
    fi
}
active_is() { [ "$(grep -xE 'axata|axata-full' "$state/active" | tr '\n' ' ')" = "$1 " ]; }
profile_is() { [ "$(cat "$work/etc/profile" 2>/dev/null)" = "$1" ]; }
amn_is() { [ "$(cat "$state/amn")" = "$1" ]; }
last_err() { tail -n1 "$work/stderr"; }

echo "1. Успешный переход на запасной профиль"
state_main
run backup
expect "код 0" '[ "$code" -eq 0 ]'
expect "файл профиля backup" 'profile_is backup'
expect "awg-quick@amn0 inactive" 'amn_is inactive'
expect "активно axata-full без axata" 'active_is axata-full'
expect "1.1.1.1 через tun0" '"$stub/ip" -4 route get 1.1.1.1 | grep -q "dev tun0"'
expect "итог в журнале" 'grep -q "проверка запасного профиля пройдена" "$work/net-profile.log"'
expect "порядок вызовов: stop, down axata, up axata-full" '[ "$(tr "\n" ";" <"$state/calls")" = "stop awg-quick@amn0.service;down axata;up axata-full;" ]'
expect "в журнале файл профиля раньше остановки amn0, остановка раньше подъёма axata-full" \
    'awk "/>>> файл профиля: backup/ { f = NR } />>> awg-quick@amn0.service остановлен/ { s = NR } />>> axata-full поднято/ { u = NR } END { exit !(f && s && u && f < s && s < u) }" "$work/net-profile.log"'

echo "2. Повторный вызов в запасном профиле"
: >"$state/calls"
run backup
expect "код 0" '[ "$code" -eq 0 ]'
expect "axata-full не переподключалось" '[ ! -s "$state/calls" ]'
expect "итог называет повторный вызов" 'grep -q "уже запасной" <<<"$out"'

echo "3. Посторонний процесс на tun0"
reset
echo inactive >"$state/amn"
printf '%s\n' "Проводное подключение 2" >"$state/active"
mkdir -p "$sys/tun0"
echo 26418 >"$state/openvpn_pids"
run backup
expect "код 3" '[ "$code" -eq 3 ]'
expect "сообщение называет tun0 и PID" 'last_err | grep -q "tun0.*26418"'
expect "файл профиля не создан" '[ ! -e "$work/etc/profile" ]'
expect "службы и соединения не трогались" '[ ! -s "$state/calls" ]'
run main
expect "main тоже: код 3" '[ "$code" -eq 3 ]'
# Соединения axata-full ещё нет: отказ всё равно кодом 3 и с PID.
printf '%s\n' "Проводное подключение 2" axata >"$state/connections"
run backup
expect "без axata-full: код 3 и PID" '[ "$code" -eq 3 ] && last_err | grep -q "26418"'

echo "4. Откат: axata-full не поднялось"
state_main
touch "$state/fail_up_axata-full"
run backup
expect "код 1" '[ "$code" -eq 1 ]'
expect "файл профиля main" 'profile_is main'
expect "awg-quick@amn0 active" 'amn_is active'
expect "активно axata" 'active_is axata'
expect "итог: ОШИБКА с причиной" 'grep -q "ОШИБКА: axata-full не поднялось" <<<"$out"'
expect "вывод ошибок: причина последней строкой" 'last_err | grep -q "ОШИБКА: axata-full не поднялось; прежний профиль возвращён"'

echo "4а. Откат: проверка запасного профиля не прошла (api.anthropic.com)"
state_main
rm -f "$work/etc/profile"
touch "$state/anthropic_down"
run backup
expect "код 1" '[ "$code" -eq 1 ]'
expect "файла профиля нет, как до вызова" '[ ! -e "$work/etc/profile" ]'
expect "awg-quick@amn0 active, активно axata" 'amn_is active && active_is axata'
expect "итог: ОШИБКА — запрос не прошёл" 'grep -q "ОШИБКА: запрос к api.anthropic.com не прошёл" <<<"$out"'

echo "4б. Откат: DNS запасного профиля не выставлен"
state_main
touch "$state/no_default_route"
run backup
expect "код 1, axata и amn0 возвращены" '[ "$code" -eq 1 ] && amn_is active && active_is axata'
expect "причина — Default Route" 'last_err | grep -q "Default Route"'

echo "5. Возврат на основной профиль"
state_backup
run main
expect "код 0" '[ "$code" -eq 0 ]'
expect "файл профиля main" 'profile_is main'
expect "awg-quick@amn0 active" 'amn_is active'
expect "активно axata без axata-full" 'active_is axata'
expect "порядок: down axata-full, up axata, restart amn0" '[ "$(tr "\n" ";" <"$state/calls")" = "down axata-full;up axata;restart awg-quick@amn0.service;" ]'
expect "в журнале файл профиля раньше запуска, запуск после подъёма axata" \
    'awk "/>>> файл профиля: main/ { f = NR } />>> axata поднято/ { a = NR } />>> awg-quick@amn0.service запущен/ { s = NR } END { exit !(f && a && s && f < s && a < s) }" "$work/net-profile.log"'

echo "5а. Повторный вызов в основном профиле"
: >"$state/calls"
run main
expect "код 0, ничего не переподключалось" '[ "$code" -eq 0 ] && [ ! -s "$state/calls" ]'

echo "6. Неудачный возврат оставляет запасной профиль"
state_backup
touch "$state/amnezia_down"
run main
expect "код 1" '[ "$code" -eq 1 ]'
expect "файл профиля backup" 'profile_is backup'
expect "awg-quick@amn0 inactive" 'amn_is inactive'
expect "активно axata-full" 'active_is axata-full'
expect "1.1.1.1 через tun0" '"$stub/ip" -4 route get 1.1.1.1 | grep -q "dev tun0"'
expect "итог: профиль остался запасным" 'last_err | grep -q "профиль остался запасным"'

echo "6а. Неудачный откат возврата"
state_backup
touch "$state/amnezia_down" "$state/fail_up_axata-full"
run main
expect "код 1, ОШИБКА отката" '[ "$code" -eq 1 ] && grep -q "ОШИБКА: откат не выполнен" <<<"$out"'
expect "состояние в журнале" 'grep -q "=== ip -4 route" "$work/net-profile.log"'

echo "6б. Неудачный повторный вызов в основном профиле оставляет основной"
state_main
touch "$state/amnezia_down"
run main
expect "код 1" '[ "$code" -eq 1 ]'
expect "файл профиля main, amn0 active, активно axata" 'profile_is main && amn_is active && active_is axata'
expect "axata-full не поднималось" '! grep -q "up axata-full" "$state/calls"'
expect "итог: профиль остался основным" 'last_err | grep -q "профиль остался основным"'

echo "7. Второй одновременный вызов отказывает"
state_main
exec 8>"$work/net-profile.lock"
flock -n 8
run main
expect "код 1" '[ "$code" -eq 1 ]'
expect "сообщение о выполняемом переходе" 'last_err | grep -q "уже выполняется"'
expect "ничего не изменено" '[ ! -s "$state/calls" ] && profile_is main'
exec 8>&-

echo "8. Чужой аргумент"
run foo
expect "код 2" '[ "$code" -eq 2 ]'
run backup extra
expect "лишний аргумент: код 2" '[ "$code" -eq 2 ]'

echo
if [ "$failures" -eq 0 ]; then
    echo "все проверки пройдены"
else
    echo "не пройдено проверок: $failures"
    exit 1
fi
