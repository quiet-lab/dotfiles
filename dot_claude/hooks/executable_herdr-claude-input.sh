#!/bin/bash
# Строка ввода Claude Code в neovim: хук `open` (SessionStart) делит панель
# Claude herdr по горизонтали, нижняя панель получает ровно 13 строк вывода
# и запускает в ней `nvim +ClaudeInput`; хук `close` (SessionEnd) закрывает
# эту панель. Соответствие «панель Claude -> панель буфера» хранит файл
# ${XDG_STATE_HOME:-~/.local/state}/claude-input/<панель Claude, ':' -> '_'>
# с идентификатором панели буфера. Аргумент — open или close.
# Хук молчит и выходит с кодом 0 при любой ошибке, вне herdr и у
# субагентов, при живой панели буфера того же workspace и когда
# панель Claude ниже 20 строк (13 строк вывода, 2 строки рамки, 5 строк Claude).
exec 2>/dev/null
mode=${1:-}
input=$(cat)
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v jq > /dev/null && command -v herdr > /dev/null || exit 0
[ -z "$(jq -r '.agent_id // empty' <<< "$input")" ] || exit 0

# Вложенный `claude -p` (например, из инструмента Bash) наследует HERDR_PANE_ID,
# но панели Claude не владеет: хук работает, только когда среди ближайших
# предков найден процесс claude с терминалом (pty) на стандартном вводе.
pid=$PPID
found=
for _ in 1 2 3 4; do
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
    if [ "$(cat "/proc/$pid/comm")" = "claude" ]; then
        found=$pid
        break
    fi
    pid=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status")
done
[ -n "$found" ] || exit 0
case "$(readlink "/proc/$found/fd/0")" in
    /dev/pts/*) ;;
    *) exit 0 ;;
esac

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/claude-input
map_file=$state_dir/${HERDR_PANE_ID//:/_}
rows_wanted=13

case "$mode" in
    close)
        [ -f "$map_file" ] || exit 0
        buffer=$(cat "$map_file")
        [ -z "$buffer" ] || herdr pane close "$buffer" > /dev/null
        rm -f "$map_file"
        exit 0
        ;;
    open) ;;
    *) exit 0 ;;
esac

# Панель буфера уже есть и жива в том же workspace — повторно не создаётся.
if [ -f "$map_file" ]; then
    old=$(cat "$map_file")
    if [ -n "$old" ]; then
        info=$(herdr pane get "$old")
        if [ -n "$info" ] && [ -z "$(jq -r '.error // empty' <<< "$info")" ]; then
            ws=$(jq -r '.result.pane.workspace_id // empty' <<< "$info")
            [ -z "${HERDR_WORKSPACE_ID:-}" ] || [ "$ws" = "$HERDR_WORKSPACE_ID" ] || old=
            [ -z "$old" ] || exit 0
        fi
    fi
fi

pane_height() {
    herdr pane layout --pane "$HERDR_PANE_ID" | jq -r --arg p "$1" \
        '.result.layout.panes[] | select(.pane_id == $p) | .rect.height // empty'
}

h=$(pane_height "$HERDR_PANE_ID")
[ -n "$h" ] && [ "$h" -ge 20 ] || exit 0
ratio=$(awk -v h="$h" 'BEGIN { printf "%.4f", (h - 15) / h }')

new_info=$(herdr pane split "$HERDR_PANE_ID" --direction down --focus \
    --ratio "$ratio" --env CLAUDE_INPUT_PANE="$HERDR_PANE_ID")
new=$(jq -r '.result.pane.pane_id // empty' <<< "$new_info")
[ -n "$new" ] || exit 0
mkdir -p "$state_dir"
printf '%s\n' "$new" > "$map_file"

# Одна поправка разделителя, если в панели не 13 строк вывода.
rows=$(jq -r '.result.pane.scroll.viewport_rows // empty' <<< "$new_info")
if [ -n "$rows" ] && [ "$rows" != "$rows_wanted" ]; then
    top=$(pane_height "$HERDR_PANE_ID")
    bottom=$(pane_height "$new")
    if [ -n "$top" ] && [ -n "$bottom" ]; then
        amount=$(awk -v r="$rows" -v w="$rows_wanted" -v t="$((top + bottom))" \
            'BEGIN { d = w - r; if (d < 0) d = -d; printf "%.4f", d / t }')
        dir=up
        [ "$rows" -lt "$rows_wanted" ] || dir=down
        herdr pane resize --pane "$new" --direction "$dir" --amount "$amount" > /dev/null
    fi
fi

herdr pane run "$new" 'exec nvim +ClaudeInput' > /dev/null
exit 0
