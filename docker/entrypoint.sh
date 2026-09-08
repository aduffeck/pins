#!/bin/sh
# Container entrypoint for pins.
#
# Started as root it prepares the per-user data directories (normally on a
# volume), refreshes the plugins bundled in the image, links the bundled sky
# map cache, clears stale runtime files and then hands over to supervisord
# (default command) or runs any other command as the `pins` user.
set -eu

app_dir="${PINS_APP_DIR:-/opt/pins}"
home=/home/pins
data_dir="$home/.local/share/NINA"
plugin_dir="$data_dir/Plugins/${PINS_PLUGIN_API_VERSION:-3.0.0}"
as_root=0
[ "$(id -u)" -eq 0 ] && as_root=1

own() {
  # chown only what this script created; a bind-mounted home keeps its owner.
  [ "$as_root" -eq 1 ] && chown pins:pins "$@" 2>/dev/null || true
}

mkdir -p "$data_dir" "$home/.config" "$home/Documents/N.I.N.A" "$home/Documents/INDI"
own "$home" "$home/.local" "$home/.local/share" "$data_dir" "$home/.config" \
    "$home/Documents" "$home/Documents/N.I.N.A" "$home/Documents/INDI"

# ASTAP star databases live on the volume (/opt/astap and /usr/share/astap/data
# point here); pins-install-astap-db fills it.
mkdir -p "$home/.local/share/astap"
own "$home/.local/share/astap"

# Earlier images linked a bundled sky map cache into the data directory; drop
# such a link when its target is gone so the cache can be downloaded again.
cache="$data_dir/FramingAssistantCache"
if [ -L "$cache" ] && [ ! -e "$cache" ]; then
  rm -f "$cache"
  echo "[pins] removed stale sky map cache link; run pins-download-skymap to fetch the cache"
fi

# Register the INDI 3rd-party drivers built into the image for Touch-N-Stars
# (entries already in the registry are kept).
registry="$home/Documents/INDI/3rdparty.json"
if [ -f /opt/pins-data/indi-3rdparty.json ] && [ "${PINS_REGISTER_INDI_DRIVERS:-1}" = "1" ]; then
  python3 /usr/local/lib/pins/indi-3rdparty-registry.py merge /opt/pins-data/indi-3rdparty.json "$registry" || true
  own "$registry"
fi

# Plugins bundled in the image are installed into the plugin folder; a folder
# of the same name is replaced only when the bundled content changed (image
# rebuild), so files a plugin keeps in its own folder survive restarts. Other
# plugins are left untouched.
if [ "${PINS_SYNC_BUNDLED_PLUGINS:-1}" = "1" ] && [ -d /opt/pins-plugins ]; then
  mkdir -p "$plugin_dir"
  own "$data_dir/Plugins" "$plugin_dir"
  for src in /opt/pins-plugins/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"
    if [ -f "$src/.pins-bundle" ] && [ -f "${plugin_dir}/${name}/.pins-bundle" ] \
       && cmp -s "$src/.pins-bundle" "${plugin_dir}/${name}/.pins-bundle"; then
      continue
    fi
    rm -rf "${plugin_dir:?}/${name}"
    cp -a "$src" "${plugin_dir}/${name}"
    [ "$as_root" -eq 1 ] && chown -R pins:pins "${plugin_dir}/${name}"
    echo "[pins] installed bundled plugin: $name"
  done
fi

# Stale runtime state from an unclean shutdown.
rm -f /tmp/indiFIFO /tmp/.X0-lock "$home/phd2.1"

if [ "$as_root" -eq 1 ]; then
  # X server socket directory for Xvfb (must exist and be owned by root).
  mkdir -p -m 1777 /tmp/.X11-unix
  mkdir -p /run/pins /opt/pinsdaemon/logs
  chown sysupdate-api:sysupdate-api /opt/pinsdaemon/logs 2>/dev/null || true
  # USB device access for the pins user (also kept up to date by the
  # supervised watcher).
  /usr/local/bin/pins-usb-permissions once || true
  # USB transfer buffer for large-sensor USB3 cameras: the ZWO SDK fails to
  # download frames bigger than usbfs_memory_mb (kernel default 16 MB; a full
  # 16 MP RAW16 frame is 32 MB) and the exposure then times out in pins. The
  # parameter is host-global; a privileged container can write it (sysfs is
  # mounted read-write there), otherwise it has to be set on the host.
  usbfs=/sys/module/usbcore/parameters/usbfs_memory_mb
  want="${PINS_USBFS_MEMORY_MB:-256}"
  if [ -f "$usbfs" ] && [ "$want" -gt 0 ] 2>/dev/null; then
    have="$(cat "$usbfs" 2>/dev/null || echo 0)"
    if [ "$have" -lt "$want" ]; then
      if echo "$want" 2>/dev/null > "$usbfs"; then
        echo "[pins] usbfs_memory_mb raised from $have to $want MB"
      else
        echo "[pins] usbfs_memory_mb is $have MB and cannot be changed from here; frames of large USB3 cameras may fail to download. On the host: echo $want > $usbfs"
      fi
    fi
  fi
  # PHD2 "enabled" state consulted by the systemctl shim (pinsdaemon).
  if [ "${PHD2_AUTOSTART:-true}" = "true" ]; then touch /run/pins/phd2.enabled; else rm -f /run/pins/phd2.enabled; fi
  chmod 755 /run/pins
fi

case "${1:-}" in
  supervisord|/usr/bin/supervisord)
    exec "$@" ;;
  *)
    cd "$app_dir"
    if [ "$as_root" -eq 1 ]; then
      exec runuser -u pins -- "$@"
    fi
    exec "$@" ;;
esac
