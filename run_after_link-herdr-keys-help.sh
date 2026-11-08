#!/usr/bin/env bash
# Регистрация плагина herdr keys-help (изменение OpenSpec herdr-keys-help, D1):
# выполняется при каждом chezmoi apply и ничего не делает, если плагин уже
# записан в plugins.json herdr. Регистрации нужен запущенный сервер herdr; без
# него сценарий сообщает об этом и завершается успешно — плагин зарегистрирует
# следующий apply или команда herdr plugin link ~/.config/herdr/plugins/keys-help.
set -uo pipefail
plugin="$HOME/.config/herdr/plugins/keys-help"
registry="$HOME/.config/herdr/plugins.json"
command -v herdr >/dev/null 2>&1 || exit 0
[[ -f $plugin/target/release/keys-help ]] || exit 0
if [[ -f $registry ]] && grep -q '"quiet-lab.keys-help"' "$registry"; then
  exit 0
fi
sock="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
if [[ -S $sock ]] && herdr plugin link "$plugin" >/dev/null 2>&1; then
  exit 0
fi
echo "keys-help: сервер herdr не запущен, плагин не зарегистрирован;" \
  "его зарегистрирует следующий chezmoi apply или herdr plugin link $plugin" >&2
exit 0
