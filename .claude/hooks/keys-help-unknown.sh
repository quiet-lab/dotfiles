#!/usr/bin/env bash
# Хук SessionStart: печатает список программ, для которых плагин keys-help
# не нашёл ни манифеста, ни таблицы универсального извлекателя
# (docs/keys-help.md, раздел «Файл неизвестных программ и порядок разбора»).
# Файл пишет просмотрщик; нет файла или он пуст — хук молчит.
set -u

file="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-keys-help/unknown-programs.toml"
[[ -s $file ]] || exit 0

list=$(awk '
  /^\[program\./ {
    flush()
    name = $0
    sub(/^\[program\./, "", name)
    sub(/\][[:space:]]*$/, "", name)
    gsub(/^"|"$/, "", name)
    count = 0; last = ""
    next
  }
  /^count[[:space:]]*=/ { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); count = v + 0; next }
  /^last[[:space:]]*=/  { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); last = v; next }
  function flush() { if (name != "") printf "%d\t%s\t%s\n", count, name, last; name = "" }
  END { flush() }
' "$file" | sort -t$'\t' -k1,1nr -k2,2)

[[ -n $list ]] || exit 0

echo "Неизвестные программы keys-help (клавиши не найдены ни манифестом, ни универсальным извлекателем):"
while IFS=$'\t' read -r count name last; do
  printf -- '- %s: запусков %s, последний %s\n' "$name" "$count" "$last"
done <<<"$list"
echo "Разбор: docs/keys-help.md, раздел «Файл неизвестных программ и порядок разбора»."
echo "Конец списка неизвестных программ."
