#!/bin/bash
# Сообщение herdr о главной сессии Claude: у панели выставляется display_agent
# (короткое имя модели), у workspace — токен цвета color=#ffffff (главный агент
# репозитория белый; fg и bg = "$color" строк sidebar берут его).
# Подпись «<символ> <место> · <приложение>» строит сам herdr: символ — по каталогу
# из [ui.workspace_symbols] конфигурации herdr, место — репозиторий, приложение —
# display_agent. Хук workspace и вкладки не переименовывает.
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

herdr pane report-metadata "$HERDR_PANE_ID" --source claude-main --display-agent "$model" > /dev/null
herdr workspace report-metadata "$HERDR_WORKSPACE_ID" --source claude-main --token color=#ffffff > /dev/null
exit 0
