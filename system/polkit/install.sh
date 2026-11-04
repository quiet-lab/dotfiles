#!/usr/bin/env bash
# Установка правила polkit 50-mne-admin.rules (README рядом).
# Права root сценарий получает сам через sudo -A (окно Quickshell askpass).
# polkitd перечитывает /etc/polkit-1/rules.d сам, перезапуск не нужен.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
exec sudo -A -p 'установить правило polkit для пользователя станции' \
    install -m 0644 -o root -g root "$here/50-mne-admin.rules" /etc/polkit-1/rules.d/50-mne-admin.rules
