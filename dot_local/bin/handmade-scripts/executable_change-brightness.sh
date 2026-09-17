#!/usr/bin/env sh

# Яркость по клавишам XF86MonBrightness*: brightnessctl и уведомление dunst.
# За основу взят скрипт из dotfiles owl4ce (https://github.com/owl4ce/dotfiles),
# настройки заданы прямо здесь, файл ~/.joyfuld больше не используется.

# SPDX-License-Identifier: ISC

# shellcheck disable=SC2016,SC2166

export LANG='POSIX'
exec >/dev/null 2>&1

# Настройки яркости.
BRIGHTNESS_DEVICE=''     # устройство brightnessctl (`brightnessctl -l`), пусто — по умолчанию
BRIGHTNESS_STEPS='5'     # шаг в процентах


[ -x "$(command -v brightnessctl)" ] || exec dunstify 'Install `brightnessctl`!' -h string:synchronous:install-deps \
                                                                                 -a hotkeys \
                                                                                 -u low

case "${1}" in
    +) brightnessctl ${BRIGHTNESS_DEVICE:+-d "$BRIGHTNESS_DEVICE"} set "${BRIGHTNESS_STEPS:-5}%+" -q
    ;;
    -) brightnessctl ${BRIGHTNESS_DEVICE:+-d "$BRIGHTNESS_DEVICE"} set "${BRIGHTNESS_STEPS:-5}%-" -q
    ;;
esac

{
    BRIGHTNESS="$(brightnessctl ${BRIGHTNESS_DEVICE:+-d "$BRIGHTNESS_DEVICE"} get -P)"

    if [ "$BRIGHTNESS" -eq 0 ]; then
        ICON='notification-display-brightness-off'
    elif [ "$BRIGHTNESS" -lt 10 ]; then
        ICON='notification-display-brightness-low'
    elif [ "$BRIGHTNESS" -lt 70 ]; then
        ICON='notification-display-brightness-medium'
    elif [ "$BRIGHTNESS" -lt 100 ]; then
        ICON='notification-display-brightness-high'
    else
        ICON='notification-display-brightness-full'
    fi

    exec dunstify "$BRIGHTNESS" -h "int:value:${BRIGHTNESS}" \
                                -a hotkeys \
                                -h string:synchronous:display-brightness \
                                -i "$ICON" \
                                -t 1000
} &

exit ${?}
