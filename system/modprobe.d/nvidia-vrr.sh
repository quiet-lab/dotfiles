#!/usr/bin/env bash
# Параметр драйвера NVIDIA conceal_vrr_caps=1: снятие, возврат и проверка
# состояния (запись решения docs/decisions/0006-nvidia-conceal-vrr-caps.md).
#
# Файл /etc/modprobe.d/nvidia-vrr.conf читается при загрузке модуля
# nvidia_modeset, а модуль загружается из initramfs, поэтому любое изменение
# файла требует пересборки образа и перезагрузки. До перезагрузки модуль
# работает с тем значением, с которым был загружен.
#
# Действия:
#   remove   убрать файл из /etc/modprobe.d и пересобрать initramfs
#   restore  вернуть файл из репозитория (root:root, 644) и пересобрать initramfs
#   status   напечатать текущее состояние: файл, параметр модуля, vrr_capable
#            в DRM и наличие файла в собранных образах initramfs
#
# Запуск из терминала одной командой, права root сценарий получает сам —
# через sudo -A с графическим запросом пароля (окно pinentry):
#   system/modprobe.d/nvidia-vrr.sh status
#   system/modprobe.d/nvidia-vrr.sh remove
#   system/modprobe.d/nvidia-vrr.sh restore
#
# Пересобирает образы та же команда, которой пользуется pacman-хук
# limine-mkinitcpio-hook, — limine-mkinitcpio. Она собирает initramfs для всех
# установленных ядер и переписывает контрольные суммы в /boot/limine.conf,
# поэтому писать образ мимо неё нельзя: limine проверяет суммы при загрузке.
# В её выводе всегда есть чужая ошибка «mkinitcpio failed for kernel
# 7.2.0-1-cachyos-bmq-lto, skipping»: для ядра linux-cachyos-bmq-lto нет пакета
# с модулями NVIDIA, и его образ не собирается с 2026-08-04. К параметру VRR это
# отношения не имеет, загрузочной записи у этого ядра нет.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/$(basename "$0")"
conf_name=nvidia-vrr.conf
src="$here/$conf_name"
dst="/etc/modprobe.d/$conf_name"
askpass=${SUDO_ASKPASS:-$HOME/.local/bin/handmade-scripts/sudo-askpass}

# Повышение прав: сценарий перезапускает сам себя через sudo -A, чтобы пароль
# спросило окно pinentry, а не терминал.
need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    if [ ! -x "$askpass" ]; then
        echo "не найдена обёртка askpass: $askpass" >&2
        exit 1
    fi
    echo "нужны права root, пароль спросит окно pinentry"
    exec env SUDO_ASKPASS="$askpass" sudo -A -- "$script" "$@"
}

# Каталог загрузки: limine-entry-tool читает ESP_PATH из /etc/default/limine.
esp_path() {
    local esp=""
    if [ -r /etc/default/limine ]; then
        esp=$(
            declare -A KERNEL_CMDLINE=()
            # shellcheck source=/dev/null
            . /etc/default/limine 2>/dev/null || true
            printf '%s' "${ESP_PATH:-}"
        )
    fi
    [ -n "$esp" ] || esp=/boot
    printf '%s' "$esp"
}

# Есть ли файл параметра в образе. Его кладёт туда хук modconf из
# /etc/mkinitcpio.conf: он копирует все *.conf из /etc/modprobe.d.
image_has_conf() {
    local img=$1 line
    while IFS= read -r line; do
        if [ "$line" = "etc/modprobe.d/$conf_name" ]; then
            return 0
        fi
    done < <(lsinitcpio "$img" 2>/dev/null)
    return 1
}

report_file() {
    echo "== файл параметра =="
    if [ -e "$dst" ]; then
        echo "$dst: есть"
        if cmp -s "$src" "$dst"; then
            echo "  содержимое совпадает с копией в репозитории"
        else
            echo "  ВНИМАНИЕ: содержимое отличается от $src"
        fi
    else
        echo "$dst: нет"
    fi
}

report_module() {
    echo "== параметр загруженного модуля nvidia_modeset =="
    local p=/sys/module/nvidia_modeset/parameters/conceal_vrr_caps
    if [ -r "$p" ]; then
        echo "conceal_vrr_caps = $(cat "$p")  (значение действует с загрузки системы)"
    elif [ -d /sys/module/nvidia_modeset ]; then
        echo "модуль загружен, но параметра conceal_vrr_caps у него нет"
    else
        echo "модуль nvidia_modeset не загружен, параметр не виден"
    fi
}

# vrr_capable — свойство разъёма DRM. Драйвер NVIDIA не показывает его
# в /sys/class/drm, поэтому значение читается modetest из пакета libdrm.
report_vrr_capable() {
    echo "== vrr_capable в DRM (modetest) =="
    if ! command -v modetest >/dev/null; then
        echo "modetest не установлен (пакет libdrm), значение не прочитать"
        return 0
    fi
    local out
    if ! out=$(modetest -M nvidia-drm -c 2>/dev/null); then
        echo "modetest не смог открыть устройство nvidia-drm"
        return 0
    fi
    # Вывод modetest: строка разъёма (поля через табуляцию), затем его режимы
    # и свойства. Значение свойства идёт следующей строкой «value: N».
    printf '%s\n' "$out" | awk '
        /^[0-9]+\t/ {
            split($0, f, "\t"); status = f[3]; name = f[4]
            sub(/ +$/, "", name); next
        }
        /vrr_capable:/ { want = 1; next }
        want && /value:/ {
            if (status == "connected") {
                printf "%s (%s): %s\n", name, status, $2
                found = 1
            }
            want = 0
        }
        END { if (!found) print "подключённых разъёмов со свойством vrr_capable нет" }
    '
}

report_initramfs() {
    echo "== файл параметра в собранных образах initramfs =="
    local esp machine_id img found=0
    esp=$(esp_path)
    if [ ! -r /etc/machine-id ]; then
        echo "нет /etc/machine-id, каталог образов не определить"
        return 0
    fi
    machine_id=$(cat /etc/machine-id)
    if ! command -v lsinitcpio >/dev/null; then
        echo "lsinitcpio не установлен (пакет mkinitcpio), содержимое образов не прочитать"
        return 0
    fi
    for img in "$esp/$machine_id"/*/initramfs "$esp/$machine_id"/*/initramfs-fallback; do
        [ -f "$img" ] || continue
        found=1
        if image_has_conf "$img"; then
            echo "$img: есть  ($(date -r "$img" '+%Y-%m-%d %H:%M'))"
        else
            echo "$img: нет  ($(date -r "$img" '+%Y-%m-%d %H:%M'))"
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo "образов в $esp/$machine_id не найдено"
    fi
}

status() {
    need_root status
    report_file
    echo
    report_module
    echo
    report_vrr_capable
    echo
    report_initramfs
}

rebuild() {
    echo "== пересборка initramfs (limine-mkinitcpio) =="
    if ! limine-mkinitcpio; then
        echo "ОШИБКА: пересборка initramfs не удалась" >&2
        echo "состояние неполное: файл в /etc и образы initramfs разошлись," >&2
        echo "перезагружаться нельзя, разберитесь с выводом выше" >&2
        return 1
    fi
}

remove() {
    need_root remove
    if [ -e "$dst" ]; then
        if [ -f "$src" ] && ! cmp -s "$src" "$dst"; then
            # Содержимое расходится с копией в репозитории — сохраняем его
            # рядом. Имя без .conf на конце, поэтому ни modprobe, ни хук
            # modconf копию не читают.
            cp -a "$dst" "$dst.bak-$(date +%F)"
            echo "содержимое отличалось от копии в репозитории, сохранено: $dst.bak-$(date +%F)"
        fi
        rm -v "$dst"
    else
        echo "$dst: файла уже нет"
    fi
    rebuild
    echo
    status
    echo
    echo "готово: перезагрузитесь, чтобы модуль загрузился без параметра;"
    echo "вернуть всё назад — $script restore и ещё одна перезагрузка"
}

restore() {
    need_root restore
    if [ ! -f "$src" ]; then
        echo "нет копии в репозитории: $src" >&2
        exit 1
    fi
    install -o root -g root -m 0644 "$src" "$dst"
    echo "записан $dst"
    rebuild
    echo
    status
    echo
    echo "готово: перезагрузитесь, чтобы модуль загрузился с параметром"
}

case "${1:-}" in
    remove) remove ;;
    restore) restore ;;
    status) status ;;
    *) echo "использование: $0 remove|restore|status" >&2; exit 2 ;;
esac
