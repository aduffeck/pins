#!/bin/sh
# Host time zone, clock, keyboard and locale settings for the pins container.
#
# Installed as /usr/bin/timedatectl and /usr/bin/localectl (the systemd
# originals are diverted, see the Dockerfile), as /usr/bin/raspi-config, and
# as /usr/local/lib/pins/host-settings (used by the entrypoint). It does what
# the invoked name says, for the subcommands pinsdaemon uses.
#
# There is no systemd in the container, so the real timedatectl and localectl
# refuse to run. In the container these settings belong to the host machine,
# so this script asks the host's timedated and localed over the host's system
# D-Bus socket, the way the power shim asks the host's logind. On a Raspberry
# Pi installation pinsdaemon changes the Pi's own settings; here the
# Touch-N-Stars "Regional settings" page shows and changes the host's.
#
# Requirements (see docker/README.md, "Host time zone and keyboard"):
#   * the host socket mounted into the container:
#       -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro
#   * a privileged container (Docker's default AppArmor profile blocks D-Bus)
#   * root: the host's bus only accepts root from the container. Callers that
#     are not root re-run this script through sudo when they may
#     (sysupdate-api, docker/sudoers-pinsdaemon).
# Without them, reading the time zone falls back to the container's own zone
# and changing anything fails with an error that says why.
#
# Setting the host clock (`set-ntp`, `set-time`, used by Touch-N-Stars' clock
# sync) turns off NTP on the host, so it is refused unless the container was
# started with PINS_HOST_CLOCK_CONTROL=true (the entrypoint leaves the flag
# file $state/host-clock-control; sudo does not pass the environment on).
#
# Locale and Wi-Fi country cannot be changed from the container. They are
# reported so that the Touch-N-Stars form, which needs every field filled,
# can be saved; docker/manage-localization.sh accepts them unchanged only.
set -eu

me="$(basename "$0")"
socket=/run/dbus/system_bus_socket
state=/run/pins
zoneinfo=/usr/share/zoneinfo
xkb_list=/usr/share/X11/xkb/rules/base.lst

td_dest=org.freedesktop.timedate1
td_path=/org/freedesktop/timedate1
ld_dest=org.freedesktop.locale1
ld_path=/org/freedesktop/locale1

fail() { echo "$me: $*" >&2; exit 1; }

# Re-run as root through sudo when this user may; returns when not possible.
elevate() {
  [ "$(id -u)" -eq 0 ] && return 0
  if sudo -n -l "/usr/bin/$me" >/dev/null 2>&1; then
    exec sudo -n "/usr/bin/$me" "$@"
  fi
  return 0
}

# host_check DEST PATH PROPERTY: can the host's service be reached? Sets
# host_error to the reason when not; no_host fails with it.
host_error=""
host_check() {
  if [ ! -S "$socket" ]; then
    host_error="$socket is not mounted (docker-compose.yml mounts it; see docker/README.md)"
    return 1
  fi
  if [ "$(id -u)" -ne 0 ]; then
    host_error="only root can reach them from inside the container"
    return 1
  fi
  if ! out="$(busctl get-property "$1" "$2" "$1" "$3" 2>&1)"; then
    case "$out" in
      *"Access denied"*|*AppArmor*) out="$out (D-Bus access is blocked; the container must run with --privileged or apparmor=unconfined)" ;;
    esac
    host_error="$out"
    return 1
  fi
  return 0
}

# getp DEST PATH PROPERTY: property value without the type signature and,
# for strings, the quotes (busctl prints `s "Europe/Berlin"`, `b true`).
getp() {
  busctl get-property "$1" "$2" "$1" "$3" | sed -e 's/^[a-z]* //' -e 's/^"\(.*\)"$/\1/'
}

no_host() { fail "the host's settings are not available: $host_error"; }

yesno() { [ "$1" = "true" ] && echo yes || echo no; }

bool_arg() {
  case "$1" in
    1|yes|true|on) echo true ;;
    0|no|false|off) echo false ;;
    *) fail "invalid boolean '$1'" ;;
  esac
}

# The container's own zone: TZ, /etc/timezone, the /etc/localtime link.
local_zone() {
  z="${TZ:-}"
  z="${z#:}"
  if [ -z "$z" ] && [ -r /etc/timezone ]; then z="$(head -n 1 /etc/timezone)"; fi
  if [ -z "$z" ]; then
    z="$(readlink /etc/localtime 2>/dev/null || true)"
    z="${z#*zoneinfo/}"
  fi
  echo "${z:-UTC}"
}

valid_zone() {
  case "$1" in
    ""|/*|*..*|*[!A-Za-z0-9._+/-]*) return 1 ;;
  esac
  [ -f "$zoneinfo/$1" ] && [ "$(head -c 4 "$zoneinfo/$1" 2>/dev/null)" = "TZif" ]
}

# Point the container's /etc/localtime at a zone (used when TZ is not set).
set_local_zone() {
  [ "$(id -u)" -eq 0 ] || return 0
  valid_zone "$1" || return 0
  if [ "$(readlink /etc/localtime 2>/dev/null || true)" != "$zoneinfo/$1" ]; then
    if ! ln -sfn "$zoneinfo/$1" /etc/localtime 2>/dev/null; then
      echo "$me: warning: cannot update the container's /etc/localtime (bind-mounted?)" >&2
    fi
  fi
  { echo "$1" > /etc/timezone; } 2>/dev/null || true
}

# Country of a time zone (zone.tab), as a stand-in Wi-Fi country.
zone_country() {
  awk -v z="$1" -F '\t' '$1 !~ /^#/ && $3 == z { print $1; exit }' "$zoneinfo/zone.tab" 2>/dev/null || true
}

host_zone_or_local() {
  if host_check "$td_dest" "$td_path" Timezone; then getp "$td_dest" "$td_path" Timezone; else local_zone; fi
}

write_file() { # write_file PATH CONTENT: atomically, world-readable
  tmp="$1.tmp.$$"
  printf '%s\n' "$2" > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$1"
}

# Host keyboard layout and locale for pinsdaemon, which reads them from files
# (DEFAULT_KEYBOARD_PATH, DEFAULT_LOCALE_PATH, SUPPORTED_LOCALES_PATH in
# docker/supervisord.conf). Refreshed at container start and after a change.
refresh_cache() {
  [ "$(id -u)" -eq 0 ] || return 0
  mkdir -p "$state"
  lang=""
  if host_check "$ld_dest" "$ld_path" Locale; then
    layout="$(getp "$ld_dest" "$ld_path" X11Layout)"
    lang="$(busctl get-property "$ld_dest" "$ld_path" "$ld_dest" Locale \
      | grep -o '"LANG=[^"]*"' | sed 's/^"LANG=\(.*\)"$/\1/' | head -n 1)"
    if [ -n "$layout" ]; then write_file "$state/keyboard" "XKBLAYOUT=\"$layout\""; else rm -f "$state/keyboard"; fi
  else
    rm -f "$state/keyboard"
  fi
  if [ -z "$lang" ]; then
    lang="$(sed -n 's/^LANG=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}$/\1/p' /etc/default/locale 2>/dev/null | head -n 1)"
  fi
  lang="${lang:-C.UTF-8}"
  write_file "$state/locale" "LANG=$lang"
  # The current locale is the only choice offered (it cannot be changed here).
  write_file "$state/supported-locales" "$lang UTF-8"
}

clock_control_allowed() {
  [ -f "$state/host-clock-control" ] || fail "setting the host clock from Touch-N-Stars is disabled in the pins container (it turns off NTP on the host). Start the container with PINS_HOST_CLOCK_CONTROL=true to allow it, or set the clock on the host."
}

# ---------------------------------------------------------------- timedatectl

td_status() {
  if host_check "$td_dest" "$td_path" Timezone; then
    zone="$(getp "$td_dest" "$td_path" Timezone)"
    printf '               Local time: %s\n' "$(TZ="$zone" date '+%a %Y-%m-%d %H:%M:%S %Z')"
    printf '           Universal time: %s\n' "$(date -u '+%a %Y-%m-%d %H:%M:%S %Z')"
    printf '                Time zone: %s (%s)\n' "$zone" "$(TZ="$zone" date '+%Z, %z')"
    printf 'System clock synchronized: %s\n' "$(yesno "$(getp "$td_dest" "$td_path" NTPSynchronized)")"
    printf '              NTP service: %s\n' "$( [ "$(getp "$td_dest" "$td_path" NTP)" = true ] && echo active || echo inactive)"
    printf '          RTC in local TZ: %s\n' "$(yesno "$(getp "$td_dest" "$td_path" LocalRTC)")"
    printf '                   Source: host (timedated over D-Bus)\n'
  else
    zone="$(local_zone)"
    printf '               Local time: %s\n' "$(TZ="$zone" date '+%a %Y-%m-%d %H:%M:%S %Z')"
    printf '           Universal time: %s\n' "$(date -u '+%a %Y-%m-%d %H:%M:%S %Z')"
    printf '                Time zone: %s (container)\n' "$zone"
    printf '                   Source: container (host not available: %s)\n' "$host_error"
  fi
}

td_show() {
  props=""
  value=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --value) value=1 ;;
      --property=*) props="$props ${1#--property=}" ;;
      -p|--property) [ "$#" -ge 2 ] || fail "$1 requires a property name"; props="$props $2"; shift ;;
      -p*) props="$props ${1#-p}" ;;
      *) fail "show: unsupported argument '$1'" ;;
    esac
    shift
  done
  props="$(echo "$props" | tr ',' ' ')"
  [ -n "$(echo "$props" | tr -d ' ')" ] || props="Timezone LocalRTC CanNTP NTP NTPSynchronized"
  reachable=0
  host_check "$td_dest" "$td_path" Timezone && reachable=1
  for p in $props; do
    case "$p" in
      Timezone)
        if [ "$reachable" -eq 1 ]; then v="$(getp "$td_dest" "$td_path" Timezone)"; else v="$(local_zone)"; fi ;;
      LocalRTC|CanNTP|NTP|NTPSynchronized)
        [ "$reachable" -eq 1 ] || no_host
        v="$(yesno "$(getp "$td_dest" "$td_path" "$p")")" ;;
      *) fail "show: property '$p' is not supported inside the pins container" ;;
    esac
    if [ "$value" -eq 1 ]; then echo "$v"; else echo "$p=$v"; fi
  done
}

td_list_timezones() {
  awk '$1 == "Z" { print $2 } $1 == "L" { print $3 }' "$zoneinfo/tzdata.zi" | sort -u
}

td_set_timezone() {
  [ "$#" -eq 1 ] || fail "set-timezone requires exactly one time zone"
  valid_zone "$1" || fail "invalid time zone '$1'"
  host_check "$td_dest" "$td_path" Timezone || no_host
  busctl call "$td_dest" "$td_path" "$td_dest" SetTimezone sb "$1" false >/dev/null
  [ -n "${TZ:-}" ] || set_local_zone "$1"
}

td_set_ntp() {
  [ "$#" -eq 1 ] || fail "set-ntp requires a boolean"
  b="$(bool_arg "$1")"
  clock_control_allowed
  host_check "$td_dest" "$td_path" Timezone || no_host
  # A host without an NTP service has nothing to turn off (timedated would
  # answer "NTP not supported", and pinsdaemon turns NTP off before set-time).
  if [ "$b" = false ] && [ "$(getp "$td_dest" "$td_path" CanNTP)" != true ]; then return 0; fi
  busctl call "$td_dest" "$td_path" "$td_dest" SetNTP bb "$b" false >/dev/null
}

td_set_time() {
  [ "$#" -eq 1 ] || fail "set-time requires a time"
  clock_control_allowed
  host_check "$td_dest" "$td_path" Timezone || no_host
  zone="$(getp "$td_dest" "$td_path" Timezone)"
  # Wall time in the host's zone, like timedatectl on the host reads it.
  secs="$(TZ="$zone" date -d "$1" +%s 2>/dev/null)" || fail "invalid time '$1'"
  busctl call "$td_dest" "$td_path" "$td_dest" SetTime xbb "${secs}000000" false false >/dev/null
}

timedatectl_main() {
  for a do
    shift
    case "$a" in --no-pager|--no-ask-password) ;; *) set -- "$@" "$a" ;; esac
  done
  verb="${1:-status}"
  [ "$#" -gt 0 ] && shift
  case "$verb" in
    list-timezones) td_list_timezones; return ;;
  esac
  elevate "$verb" "$@"
  case "$verb" in
    status) td_status ;;
    show) td_show "$@" ;;
    set-timezone) td_set_timezone "$@" ;;
    set-ntp) td_set_ntp "$@" ;;
    set-time) td_set_time "$@" ;;
    *) fail "'$verb' is not supported inside the pins container" ;;
  esac
}

# ------------------------------------------------------------------ localectl

ld_list_layouts() {
  awk '/^! / { s = ($0 == "! layout"); next } s && NF { print $1 }' "$xkb_list" | sort -u
}

ld_status() {
  host_check "$ld_dest" "$ld_path" Locale || no_host
  printf '   System Locale: %s\n' "$(busctl get-property "$ld_dest" "$ld_path" "$ld_dest" Locale \
    | sed -e 's/^as [0-9]* //' -e 's/" "/\n                  /g' -e 's/"//g')"
  v="$(getp "$ld_dest" "$ld_path" VConsoleKeymap)"
  printf '       VC Keymap: %s\n' "${v:-(unset)}"
  for p in Layout Model Variant Options; do
    v="$(getp "$ld_dest" "$ld_path" "X11$p")"
    [ -z "$v" ] || printf '%16s: %s\n' "X11 $p" "$v"
  done
}

ld_set_x11_keymap() {
  [ "$#" -ge 1 ] && [ "$#" -le 4 ] || fail "set-x11-keymap requires LAYOUT [MODEL [VARIANT [OPTIONS]]]"
  ld_list_layouts | grep -Fxq "$1" || fail "unknown keyboard layout '$1'"
  host_check "$ld_dest" "$ld_path" Locale || no_host
  # convert=true: the host's console keymap follows, like localectl does by default.
  busctl call "$ld_dest" "$ld_path" "$ld_dest" SetX11Keyboard ssssbb \
    "$1" "${2:-}" "${3:-}" "${4:-}" true false >/dev/null
  refresh_cache
}

localectl_main() {
  for a do
    shift
    case "$a" in --no-pager|--no-ask-password|--no-convert) ;; *) set -- "$@" "$a" ;; esac
  done
  verb="${1:-status}"
  [ "$#" -gt 0 ] && shift
  case "$verb" in
    list-x11-keymap-layouts) ld_list_layouts; return ;;
  esac
  elevate "$verb" "$@"
  case "$verb" in
    status) ld_status ;;
    set-x11-keymap) ld_set_x11_keymap "$@" ;;
    *) fail "'$verb' is not supported inside the pins container" ;;
  esac
}

# --------------------------------------------------------------- raspi-config

# Only `nonint get_wifi_country`, for pinsdaemon's regional settings: the
# host's Wi-Fi regulatory country when it has one set, otherwise the country
# of the host's time zone.
raspi_config_main() {
  [ "$*" = "nonint get_wifi_country" ] || fail "'$*' is not supported inside the pins container"
  country=""
  if command -v iw >/dev/null 2>&1; then
    country="$(iw reg get 2>/dev/null | awk '/^global/ { g = 1; next } g && /^country / { print substr($2, 1, 2); exit }')"
  fi
  case "$country" in [A-Z][A-Z]) ;; *) country="" ;; esac
  [ -n "$country" ] || country="$(zone_country "$(host_zone_or_local)")"
  [ -n "$country" ] || exit 1
  echo "$country"
}

# ---------------------------------------------------------------- entrypoint

# `host-settings startup` (root, before the services start): cache the host's
# keyboard and locale for pinsdaemon and, unless TZ is set, give the container
# the host's time zone.
startup() {
  refresh_cache
  if host_check "$td_dest" "$td_path" Timezone; then
    zone="$(getp "$td_dest" "$td_path" Timezone)"
    if [ -n "${TZ:-}" ]; then
      echo "[pins] time zone $TZ (TZ); the host uses $zone, which Touch-N-Stars shows and changes"
    else
      set_local_zone "$zone"
      echo "[pins] time zone $zone (from the host)"
    fi
  else
    echo "[pins] time zone $(local_zone) (container); the host's settings are not available: $host_error"
  fi
}

case "$me" in
  timedatectl) timedatectl_main "$@" ;;
  localectl) localectl_main "$@" ;;
  raspi-config) raspi_config_main "$@" ;;
  host-settings)
    case "${1:-}" in
      startup) startup ;;
      refresh) refresh_cache ;;
      *) fail "usage: host-settings startup|refresh" ;;
    esac ;;
  *) fail "unknown command name" ;;
esac
