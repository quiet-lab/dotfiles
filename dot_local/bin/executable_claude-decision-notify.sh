#!/usr/bin/env bash
# Системное уведомление Claude Code, когда нужно решение пользователя.
# Хук Notification (JSON на stdin: notification_type, message, session_id, cwd, title).
# На время пробы matcher в ~/.claude/settings.json пустой (все типы);
# целевой matcher: permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input
# Тип idle_prompt уведомления не даёт никогда.
set -u
input="$(cat)"
command -v jq >/dev/null || exit 0

# Строка журнала временная: снимается после пробы AskUserQuestion.
printf '%s\n' "$(printf '%s' "$input" | jq -c .)" >> "$HOME/.claude/notify-probe.jsonl"

type="$(jq -r '.notification_type // "unknown"' <<<"$input")"
[ "$type" = "idle_prompt" ] && exit 0
message="$(jq -r '.message // ""' <<<"$input")"
sid="$(jq -r '.session_id // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"

title="Claude: $(basename "${cwd:-?}") [${sid:0:8}]"
# Workspace и панель herdr, если сессия запущена в нём.
[ -n "${HERDR_WORKSPACE_ID:-}" ] && title="$title ws=${HERDR_WORKSPACE_ID}${HERDR_PANE_ID:+ pane=${HERDR_PANE_ID}}"

notify-send -u critical -a "Claude Code" "$title" "$type: $message"
# Звук в фоне, чтобы не задерживать хук.
if command -v pw-play >/dev/null; then
  pw-play /usr/share/sounds/freedesktop/stereo/dialog-warning.oga >/dev/null 2>&1 &
elif command -v paplay >/dev/null; then
  paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga >/dev/null 2>&1 &
fi
