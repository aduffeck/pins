#!/bin/sh
# PHD2 launcher for the container.
#
# Waits for the virtual X display, clears a stale instance lock (as the pins
# systemd unit does) and runs PHD2. On SIGTERM/SIGINT (supervisord stop) PHD2
# is asked to close through its server API, which makes it flush its settings
# (~/.PHDGuidingV2) like a normal exit does; a plain signal would kill it
# without saving.
set -u

display="${DISPLAY:-:0}"
socket="/tmp/.X11-unix/X${display#:}"
port="${PHD2_SERVER_PORT:-4400}"

i=0
while [ ! -S "$socket" ]; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "pins-phd2: X display $display did not come up" >&2
    exit 1
  fi
  sleep 0.5
done

rm -f "${HOME}/phd2.1"

/usr/bin/phd2 "$@" &
child=$!

stop() {
  echo "pins-phd2: asking PHD2 to shut down"
  python3 - "$port" <<'EOF' 2>/dev/null || true
import json, socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=3)
s.sendall((json.dumps({"method": "shutdown", "id": 1}) + "\r\n").encode())
try:
    s.recv(4096)
except OSError:
    pass
s.close()
EOF
  i=0
  while kill -0 "$child" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 40 ]; then
      echo "pins-phd2: PHD2 did not exit in time, terminating" >&2
      kill -TERM "$child" 2>/dev/null || true
      break
    fi
    sleep 0.5
  done
}

trap stop TERM INT
wait "$child"
status=$?
# A trapped signal interrupts `wait` (status > 128); after the handler asked
# PHD2 to close, wait again to report PHD2's own exit status.
if [ "$status" -gt 128 ]; then
  trap - TERM INT
  wait "$child"
  status=$?
fi
exit "$status"
