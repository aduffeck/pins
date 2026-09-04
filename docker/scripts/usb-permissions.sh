#!/bin/sh
# Make the USB devices of the vendors covered by the udev rules shipped in the
# image (ZWO, QHY, ToupTek, Player One, SVBony, Atik, ...) accessible to the
# unprivileged pins user.
#
# Device nodes under /dev/bus/usb keep the host's ownership and mode inside
# the container, and the host usually has no vendor udev rules, so the nodes
# are root-only. udev does not run in a container; this script does its job
# for the vendors the rules know: it sets mode 0666 on matching nodes, once at
# start and, in watch mode, whenever a device is plugged in.
#
# Usage: pins-usb-permissions [once|watch]
set -eu

rules_dir=/usr/lib/udev/rules.d
mode="${1:-once}"

collect_vendors() {
  cat "$rules_dir"/*.rules 2>/dev/null \
    | grep -o -i -E '(ATTRS?|SYSFS)\{idVendor\}=="[0-9a-f]{4}"' \
    | grep -o -E '[0-9a-fA-F]{4}"$' | tr -d '"' | tr 'A-F' 'a-f' | sort -u
}

apply() {
  vendors="$(collect_vendors)"
  [ -n "$vendors" ] || return 0
  for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] || continue
    vendor="$(tr 'A-F' 'a-f' < "$dev/idVendor")"
    echo "$vendors" | grep -q -x "$vendor" || continue
    node="/dev/bus/usb/$(printf '%03d' "$(cat "$dev/busnum")")/$(printf '%03d' "$(cat "$dev/devnum")")"
    [ -c "$node" ] || continue
    if [ "$(stat -c %a "$node")" != "666" ]; then
      chmod 0666 "$node" && echo "usb-permissions: $node ($vendor:$(cat "$dev/idProduct"), $(cat "$dev/product" 2>/dev/null || echo '?')) -> 0666"
    fi
  done
}

apply

if [ "$mode" = "watch" ]; then
  if ! command -v inotifywait >/dev/null 2>&1; then
    echo "usb-permissions: inotifywait not available; devices plugged in later are not handled" >&2
    exec sleep infinity
  fi
  inotifywait -m -q -r -e create -e attrib /dev/bus/usb | while read -r _; do
    sleep 0.5
    apply
  done
fi
