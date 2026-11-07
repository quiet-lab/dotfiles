#!/bin/bash
# Строка ввода Claude Code в neovim: хук `open` (SessionStart) делит панель
# Claude herdr по горизонтали, нижняя панель получает ровно 13 строк вывода
# и запускает в ней `nvim +ClaudeInput`; хук `close` (SessionEnd) закрывает
# эту панель; хук `reopen` (команда /input-reopen) закрывает панель буфера
# и открывает её заново. Соответствие «панель Claude -> панель буфера» хранит файл
# ${XDG_STATE_HOME:-~/.local/state}/claude-input/<панель Claude, ':' -> '_'>
# с идентификатором панели буфера. Аргумент — open, close или reopen.
# Хук молчит и выходит с кодом 0 при любой ошибке, вне herdr и у
# субагентов, при живой панели буфера того же workspace и когда
# панель Claude ниже 20 строк (13 строк вывода, 2 строки рамки, 5 строк Claude).
# Исключение — отсутствие `herdr pane activate`: хук пишет сообщение в stderr
# через дескриптор 3 (остальной stderr отброшен) и выходит с кодом 1, чтобы
# Claude Code показал его (stderr SessionStart виден только при ненулевом коде;
# код 1 — ошибка без блокировки, сессия продолжается). Режим reopen вызывается
# пользователем, поэтому о невозможности открыть панель сообщает так же
# (дескриптор 3, код 1), а об успехе печатает идентификатор новой панели.
exec 3>&2 2>/dev/null
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

# Фокус на панель ввода без переключения клиента пользователя на чужой
# workspace: делим с --no-focus, активируем после запуска nvim командой
# `herdr pane activate`. Без неё панель не открывается: ошибка в stderr.
if ! herdr pane activate --help > /dev/null 2>&1; then
    echo "herdr-claude-input: у herdr нет команды pane activate, панель ввода не открыта" >&3
    exit 1
fi

pane_height() {
    herdr pane layout --pane "$HERDR_PANE_ID" | jq -r --arg p "$1" \
        '.result.layout.panes[] | select(.pane_id == $p) | .rect.height // empty'
}

# Высота, которую получит панель Claude после закрытия панели буфера: у режима
# reopen она измеряется до закрытия (раскладка после `pane close` обновляется
# не сразу), у режима open остаётся пустой и читается ниже.
total=

case "$mode" in
    close)
        [ -f "$map_file" ] || exit 0
        buffer=$(cat "$map_file")
        [ -z "$buffer" ] || herdr pane close "$buffer" > /dev/null
        rm -f "$map_file"
        exit 0
        ;;
    open) ;;
    reopen)
        # Панель буфера — из файла соответствия, при его отсутствии — из токена
        # input_pane панели Claude. Зависший nvim закрывает сама панель herdr.
        buffer=
        [ ! -f "$map_file" ] || buffer=$(cat "$map_file")
        [ -n "$buffer" ] || buffer=$(herdr pane get "$HERDR_PANE_ID" |
            jq -r '.result.pane.tokens.input_pane // empty')
        # Закрывается только живая панель того же workspace: идентификатор
        # из устаревшего файла мог достаться чужой панели.
        if [ -n "$buffer" ]; then
            info=$(herdr pane get "$buffer")
            ws=$(jq -r '.result.pane.workspace_id // empty' <<< "$info")
            if [ -n "$ws" ] && [ "$ws" = "${HERDR_WORKSPACE_ID:-$ws}" ]; then
                top=$(pane_height "$HERDR_PANE_ID")
                bottom=$(pane_height "$buffer")
                if [ -n "$top" ] && [ -n "$bottom" ]; then
                    total=$((top + bottom))
                fi
                herdr pane close "$buffer" > /dev/null
            fi
        fi
        rm -f "$map_file"
        ;;
    *) exit 0 ;;
esac

# Для reopen невозможность открыть панель — ошибка с сообщением, не тишина.
fail_open() {
    [ "$mode" != reopen ] || {
        echo "herdr-claude-input: $1" >&3
        exit 1
    }
    exit 0
}

# Панель буфера уже есть и жива в том же workspace — повторно не создаётся.
if [ -f "$map_file" ]; then
    old=$(cat "$map_file")
    if [ -n "$old" ]; then
        info=$(herdr pane get "$old")
        if [ -n "$info" ] && [ -z "$(jq -r '.error // empty' <<< "$info")" ]; then
            ws=$(jq -r '.result.pane.workspace_id // empty' <<< "$info")
            [ -z "${HERDR_WORKSPACE_ID:-}" ] || [ "$ws" = "$HERDR_WORKSPACE_ID" ] || old=
            if [ -n "$old" ]; then
                # Возобновлённая сессия получает токен заново (идемпотентно).
                herdr pane report-metadata "$HERDR_PANE_ID" --source claude-input \
                    --token input_pane="$old" > /dev/null
                exit 0
            fi
        fi
    fi
fi

h=${total:-$(pane_height "$HERDR_PANE_ID")}
[ -n "$h" ] && [ "$h" -ge 20 ] || fail_open "панель Claude ниже 20 строк, панель ввода не открыта"
ratio=$(awk -v h="$h" 'BEGIN { printf "%.4f", (h - 15) / h }')

new_info=$(herdr pane split "$HERDR_PANE_ID" --direction down --no-focus \
    --ratio "$ratio" --env CLAUDE_INPUT_PANE="$HERDR_PANE_ID")
new=$(jq -r '.result.pane.pane_id // empty' <<< "$new_info")
[ -n "$new" ] || fail_open "herdr не создал панель ввода"
mkdir -p "$state_dir"
printf '%s\n' "$new" > "$map_file"

# Токен для форка herdr на панели Claude Code: снимок клиента несёт токены
# только панелей с агентом. Ошибка (herdr без --token) хук не прерывает.
herdr pane report-metadata "$HERDR_PANE_ID" --source claude-input \
    --token input_pane="$new" > /dev/null

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
herdr pane activate "$new" > /dev/null
[ "$mode" != reopen ] || echo "панель ввода открыта заново: $new"
exit 0
