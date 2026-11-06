#!/bin/bash
# Подпись главной сессии Claude в herdr: workspace и вкладка получают
# «<символ> <репозиторий или папка> · <модель>» (символ — symbols.main
# конфигурации duty проекта; без конфигурации и вне репозитория символа
# нет и подпись «<репозиторий или папка> · <модель>»), у панели выставляется display_agent,
# у workspace — токен цвета color=#ffffff (главный агент репозитория белый).
# Исполнители duty:worker и субагенты пропускаются: их подписывает dispatch.sh.
# Workspace исполнителя узнаётся по токену цвета не #ffffff, а не по имени:
# подпись главной сессии другого репозитория перезаписывается.
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

# Корень проекта — по cwd сессии, а не по переменным окружения хука.
symbol=
cfg=$(ls ~/.claude/plugins/cache/*/duty/*/scripts/duty_config.py | sort -V | tail -n 1)
[ -z "$cfg" ] || symbol=$(env -u DUTY_PROJECT -u CLAUDE_PROJECT_DIR python3 -I "$cfg" --cwd "$cwd" get symbols.main --default '') || symbol=
label="$place · $model"
[ -z "$symbol" ] || label="$symbol $place · $model"
# Workspace исполнителя (dispatch.sh ставит токен цвета не белого) не трогаем.
color=$(herdr workspace list | jq -r --arg w "$HERDR_WORKSPACE_ID" '.result.workspaces[] | select(.workspace_id == $w) | .tokens.color // empty')
[ -z "$color" ] || [ "$color" = "#ffffff" ] || exit 0

herdr workspace rename "$HERDR_WORKSPACE_ID" "$label" > /dev/null
tab=$(herdr pane get "$HERDR_PANE_ID" | jq -r '.result.pane.tab_id // empty')
[ -z "$tab" ] || herdr tab rename "$tab" "$label" > /dev/null
herdr pane report-metadata "$HERDR_PANE_ID" --source claude-main --display-agent "$model" > /dev/null
herdr workspace report-metadata "$HERDR_WORKSPACE_ID" --source claude-main --token color=#ffffff > /dev/null
exit 0
