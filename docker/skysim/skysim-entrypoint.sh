#!/bin/bash
# Entrypoint of the Sky Simulator sidecar: makes the (possibly freshly created)
# home volume writable for the sim user, then runs the command as that user.
set -eu

home=/home/sim
if [ "$(id -u)" -eq 0 ]; then
  # X socket directory (Xvfb only creates it as root) and leftovers of a
  # previous run of this container, which would block the display.
  mkdir -p /tmp/.X11-unix
  chmod 1777 /tmp/.X11-unix
  n="${SKYSIM_DISPLAY:-:77}"
  n="${n#:}"
  rm -f "/tmp/.X${n}-lock" "/tmp/.X11-unix/X${n}"

  mkdir -p "$home/.config/sky_simulator"
  if [ "$(stat -c %u "$home")" != "$(id -u sim)" ]; then
    chown -R sim:sim "$home"
  fi
  chown sim:sim "$home/.config" "$home/.config/sky_simulator"
  exec setpriv --reuid=sim --regid=sim --init-groups -- "$@"
fi
exec "$@"
