#!/bin/bash
# Подпись главной сессии Claude в herdr: workspace и вкладка получают
# «<репозиторий или папка> · <модель>», у панели выставляется display_agent.
# Исполнители duty:worker и субагенты пропускаются: их подписывает dispatch.sh.
# Хук молчит и выходит с кодом 0 при любой ошибке и вне herdr.
exec 2>/dev/null
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] || exit 0
[ -z "${DUTY_TASK:-}" ] || exit 0
command -v jq > /dev/null && command -v herdr > /dev/null || exit 0

input=$(cat)
[ -z "$(jq -r '.agent_id // empty' <<< "$input")" ] || exit 0
[ -z "${HERDR_LABEL_DUMP:-}" ] || printf '%s\n' "$input" > "$HERDR_LABEL_DUMP"

cwd=$(jq -r '.cwd // empty' <<< "$input")
[ -n "$cwd" ] || cwd=$PWD
root=$(git -C "$cwd" rev-parse --show-toplevel) || root=$cwd
place=$(basename "$root")

short_model() {
    case "$1" in
        *fable*) echo fable ;;
        *opus*) echo opus ;;
        *sonnet*) echo sonnet ;;
        *haiku*) echo haiku ;;
        *) return 1 ;;
    esac
}
model=
for cand in "$(jq -r '.model // empty' <<< "$input")" \
    "$(jq -r '.model // empty' ~/.claude/settings.json)" \
    "${ANTHROPIC_MODEL:-}" "${CLAUDE_MODEL:-}"; do
    [ -n "$cand" ] || continue
    model=$(short_model "$cand") && break
done
[ -n "$model" ] || model=claude

label="$place · $model"
# Уже подписанный «имя · модель» workspace исполнителя не трогаем.
current=$(herdr workspace list | jq -r --arg w "$HERDR_WORKSPACE_ID" '.result.workspaces[] | select(.workspace_id == $w) | .label')
case $current in *" · "*) [ "$current" = "$label" ] || exit 0 ;; esac

herdr workspace rename "$HERDR_WORKSPACE_ID" "$label" > /dev/null
tab=$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.tab_id // empty')
[ -z "$tab" ] || herdr tab rename "$tab" "$label" > /dev/null
herdr pane report-metadata "$HERDR_PANE_ID" --source claude-main --display-agent "$model" > /dev/null
exit 0
