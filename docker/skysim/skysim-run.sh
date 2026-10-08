#!/bin/bash
# Runs Sky Simulator on a virtual X display and presses its "Start simulation"
# button, which opens the INDI (127.0.0.1:7625) and Alpaca (127.0.0.1:11111)
# servers. Exits when Sky Simulator exits, so the container restarts it.
#
# Settings live in ~/.config/sky_simulator/sky_simulator.cfg, seeded from the
# image default on first start (Sky Simulator cannot create the folder
# itself). Change them in the GUI (SKYSIM_VNC=true, then "Save settings") or
# edit the file and restart the container.
set -u

display="${SKYSIM_DISPLAY:-:77}"
socket="/tmp/.X11-unix/X${display#:}"
cfg_dir="$HOME/.config/sky_simulator"
cfg="$cfg_dir/sky_simulator.cfg"
export DISPLAY="$display"

pids=()
stop() {
  kill "${pids[@]}" 2>/dev/null
  wait
  exit "${1:-0}"
}
trap stop TERM INT

Xvfb "$display" -screen 0 1600x1000x24 -nolisten tcp &
pids+=($!)
for _ in $(seq 1 30); do
  [ -S "$socket" ] && break
  sleep 1
done
if [ ! -S "$socket" ]; then
  echo "skysim: X display $display did not come up (display number taken? set SKYSIM_DISPLAY)" >&2
  exit 1
fi

if [ "${SKYSIM_VNC:-false}" = "true" ]; then
  auth=(-nopw)
  [ -n "${SKYSIM_VNC_PASSWORD:-}" ] && auth=(-passwd "$SKYSIM_VNC_PASSWORD")
  x11vnc -display "$display" -forever -shared -noxdamage -quiet -rfbport "${SKYSIM_VNC_PORT:-5900}" "${auth[@]}" &
  pids+=($!)
fi

mkdir -p "$cfg_dir"
if [ ! -s "$cfg" ]; then
  cp /opt/sky_simulator/default.cfg "$cfg"
  echo "skysim: seeded $cfg"
fi
indi_port="$(sed -n 's/^indi_port=\([0-9]\+\).*/\1/p' "$cfg" | head -1)"
indi_port="${indi_port:-7625}"

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

if port_open "$indi_port"; then
  echo "skysim: port $indi_port is already in use (another Sky Simulator?)" >&2
fi

/opt/sky_simulator/sky_simulator &
sim=$!
pids+=($sim)

# The window opens at the position stored in the settings with the button at
# the bottom left; reset position and size, then click it until the server is up.
started=0
for _ in $(seq 1 30); do
  sleep 2
  if port_open "$indi_port"; then started=1; break; fi
  kill -0 "$sim" 2>/dev/null || break
  win="$(xdotool search --name '^Sky simulator for' 2>/dev/null | head -1)"
  [ -n "$win" ] || continue
  xdotool windowmove "$win" 0 0 windowsize "$win" 1353 664 windowraise "$win" 2>/dev/null
  xdotool mousemove --window "$win" 183 627 click 1 2>/dev/null
  sleep 3
done
if [ "$started" -eq 1 ]; then
  echo "skysim: simulation running, INDI server on 127.0.0.1:$indi_port"
else
  echo "skysim: INDI server did not come up on port $indi_port (devices set to Indi? check the GUI with SKYSIM_VNC=true)" >&2
fi

wait "$sim"
echo "skysim: Sky Simulator exited" >&2
stop 1
