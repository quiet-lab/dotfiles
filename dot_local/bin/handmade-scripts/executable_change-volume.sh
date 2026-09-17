#!/usr/bin/env sh

# Громкость по клавишам XF86Audio*: amixer и уведомление dunst.
# За основу взят скрипт из dotfiles owl4ce (https://github.com/owl4ce/dotfiles),
# настройки заданы прямо здесь, файл ~/.joyfuld больше не используется.

# SPDX-License-Identifier: ISC

# shellcheck disable=SC2016,SC2166

export LANG='POSIX'
exec >/dev/null 2>&1

# Настройки громкости.
AUDIO_DEVICE='pulse'     # устройство amixer (`aplay -L`), пусто — по умолчанию
AUDIO_VOLUME_STEPS='5'   # шаг в процентах


[ -x "$(command -v amixer)" ] || exec dunstify 'Install `alsa-utils`!' -h string:synchronous:install-deps \
                                                                       -a hotkeys \
                                                                       -u low

case "${1}" in
    +) amixer ${AUDIO_DEVICE:+-D "$AUDIO_DEVICE"} sset Master "${AUDIO_VOLUME_STEPS:-5}%+" on -q
    ;;
    -) amixer ${AUDIO_DEVICE:+-D "$AUDIO_DEVICE"} sset Master "${AUDIO_VOLUME_STEPS:-5}%-" on -q
    ;;
    0) amixer ${AUDIO_DEVICE:+-D "$AUDIO_DEVICE"} sset Master 1+ toggle -q
    ;;
esac

{
    AUDIO_VOLUME="$(amixer ${AUDIO_DEVICE:+-D "$AUDIO_DEVICE"} sget Master)"
    AUDIO_MUTED="${AUDIO_VOLUME##*\ \[on\]}"
    AUDIO_VOLUME="${AUDIO_VOLUME#*\ \[}" \
    AUDIO_VOLUME="${AUDIO_VOLUME%%\%\]\ *}"

    if [ "$AUDIO_VOLUME" -eq 0 -o -n "$AUDIO_MUTED" ]; then
        [ -z "$AUDIO_MUTED" ] || MUTED='Muted'
        ICON='notification-audio-volume-muted'
    elif [ "$AUDIO_VOLUME" -lt 30 ]; then
        ICON='notification-audio-volume-low'
    elif [ "$AUDIO_VOLUME" -lt 70 ]; then
        ICON='notification-audio-volume-medium'
    else
        ICON='notification-audio-volume-high'
    fi

    exec dunstify ${MUTED:-"$AUDIO_VOLUME" -h "int:value:${AUDIO_VOLUME}"} \
                                           -a hotkeys \
                                           -h string:synchronous:audio-volume \
                                           -i "$ICON" \
                                           -t 1000
} &

exit ${?}
