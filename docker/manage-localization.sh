#!/bin/sh
# Container version of pinsdaemon's manage-localization.sh, installed over the
# one from the pinsdaemon sources (see the Dockerfile). pinsdaemon runs it
# through sudo when the Touch-N-Stars "Regional settings" form is saved.
#
# The time zone and the keyboard layout are changed on the host, through the
# timedatectl and localectl shims (docker/host-settings.sh). The locale and
# the Wi-Fi country cannot be changed from the container: the form sends
# every field, so an unchanged value is accepted and a changed one fails
# before anything is applied.
set -eu

export LC_ALL=C
export LANG=C

state=/run/pins
LOCALE_VALUE=""
WIFI_COUNTRY_VALUE=""
TIMEZONE_VALUE=""
KEYBOARD_LAYOUT_VALUE=""
HAS_VALUE=0

fail() {
    printf 'Localization error: %s\n' "$1" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --locale|--wifi-country|--timezone|--keyboard-layout)
            [ "$#" -ge 2 ] || fail "$1 requires a value"
            case "$1" in
                --locale) LOCALE_VALUE=$2 ;;
                --wifi-country) WIFI_COUNTRY_VALUE=$2 ;;
                --timezone) TIMEZONE_VALUE=$2 ;;
                --keyboard-layout) KEYBOARD_LAYOUT_VALUE=$2 ;;
            esac
            HAS_VALUE=1
            shift 2
            ;;
        *)
            fail "unsupported argument: $1"
            ;;
    esac
done

[ "$HAS_VALUE" -eq 1 ] || fail "at least one localization value is required"

read_assignment() { # FILE KEY
    sed -n "s/^$2=[\"']\{0,1\}\([^\"']*\)[\"']\{0,1\}\$/\1/p" "$1" 2>/dev/null | head -n 1
}

# Check everything first, so that a refused field does not leave the others
# half applied.
if [ -n "$LOCALE_VALUE" ]; then
    CURRENT_LOCALE=$(read_assignment "$state/locale" LANG)
    [ "$LOCALE_VALUE" = "$CURRENT_LOCALE" ] \
        || fail "the locale cannot be changed from inside the pins container; change it on the host (localectl set-locale). Current: ${CURRENT_LOCALE:-unknown}"
fi

if [ -n "$WIFI_COUNTRY_VALUE" ]; then
    CURRENT_COUNTRY=$(raspi-config nonint get_wifi_country 2>/dev/null || true)
    [ "$WIFI_COUNTRY_VALUE" = "$CURRENT_COUNTRY" ] \
        || fail "the Wi-Fi country cannot be changed from inside the pins container; set it on the host. Current: ${CURRENT_COUNTRY:-unknown}"
fi

if [ -n "$TIMEZONE_VALUE" ]; then
    case "$TIMEZONE_VALUE" in
        /*|*..*|*[!A-Za-z0-9._+/-]*) fail "invalid timezone syntax" ;;
    esac
    [ -f "/usr/share/zoneinfo/$TIMEZONE_VALUE" ] || fail "unsupported timezone"
fi

if [ -n "$KEYBOARD_LAYOUT_VALUE" ]; then
    printf '%s' "$KEYBOARD_LAYOUT_VALUE" | grep -Eq '^[a-z0-9_-]+$' \
        || fail "invalid keyboard layout syntax"
    localectl list-x11-keymap-layouts | grep -Fxq "$KEYBOARD_LAYOUT_VALUE" \
        || fail "unsupported keyboard layout"
fi

[ -z "$LOCALE_VALUE" ] || printf 'Locale unchanged (%s)\n' "$LOCALE_VALUE"
[ -z "$WIFI_COUNTRY_VALUE" ] || printf 'Wi-Fi country unchanged (%s)\n' "$WIFI_COUNTRY_VALUE"

if [ -n "$TIMEZONE_VALUE" ]; then
    CURRENT_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
    if [ "$CURRENT_TIMEZONE" = "$TIMEZONE_VALUE" ]; then
        printf 'Timezone already set to %s\n' "$TIMEZONE_VALUE"
    else
        printf 'Setting the host time zone to %s\n' "$TIMEZONE_VALUE"
        timedatectl set-timezone "$TIMEZONE_VALUE" || fail "could not set the time zone"
        printf 'pins and PHD2 use the new time zone after the container restarts\n'
    fi
fi

if [ -n "$KEYBOARD_LAYOUT_VALUE" ]; then
    CURRENT_KEYBOARD=$(read_assignment "$state/keyboard" XKBLAYOUT)
    if [ "$CURRENT_KEYBOARD" = "$KEYBOARD_LAYOUT_VALUE" ]; then
        printf 'Keyboard layout already set to %s\n' "$KEYBOARD_LAYOUT_VALUE"
    else
        # Keep the host's keyboard model and options; the variant belongs to
        # the old layout.
        STATUS=$(localectl status 2>/dev/null || true)
        MODEL=$(printf '%s\n' "$STATUS" | sed -n 's/^ *X11 Model: //p' | head -n 1)
        OPTIONS=$(printf '%s\n' "$STATUS" | sed -n 's/^ *X11 Options: //p' | head -n 1)
        printf 'Setting the host keyboard layout to %s\n' "$KEYBOARD_LAYOUT_VALUE"
        localectl set-x11-keymap "$KEYBOARD_LAYOUT_VALUE" "$MODEL" "" "$OPTIONS" \
            || fail "could not set the keyboard layout"
    fi
fi

printf 'System localization update completed successfully.\n'
