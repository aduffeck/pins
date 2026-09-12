#!/bin/sh
# Start a pins container from the given image, wait for the server to come up
# and verify the core endpoints, the bundled plugins, INDI, PHD2, pinsdaemon,
# ASTAP and the sky map cache. Removes the container (and its throwaway
# volume) afterwards.
#
# Usage: smoke-test.sh [IMAGE] [TIMEOUT_SECONDS]
set -eu

image="${1:-pins:local}"
timeout="${2:-180}"
name="pins-smoke-$$"
volume="${name}-home"
rc=0

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

say() { printf '[smoke] %s\n' "$*"; }
check() {
  if "$@"; then say "ok:   $*"; else say "FAIL: $*"; rc=1; fi
}
soft() {
  if "$@"; then say "ok:   $*"; else say "warn: $* (not fatal)"; fi
}
in_container() { docker exec "$name" sh -c "$1"; }
port_open() { curl -s --max-time 3 -o /dev/null "http://127.0.0.1:$1/" 2>/dev/null; [ $? -ne 7 ]; }

say "starting $image as $name (host networking)"
docker run -d --name "$name" --network host -v "$volume:/home/pins" "$image" >/dev/null

say "waiting up to ${timeout}s for the core server on port 4782"
elapsed=0
until curl -s -o /dev/null http://127.0.0.1:4782/ 2>/dev/null; do
  if [ "$elapsed" -ge "$timeout" ]; then
    say "FAIL: server did not come up within ${timeout}s"
    docker logs "$name" 2>&1 | tail -n 40
    exit 1
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
    say "FAIL: container exited"
    docker logs "$name" 2>&1 | tail -n 40
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
say "core server up after ${elapsed}s"

# Give plugins and the other services a moment to start their listeners.
sleep 10

check in_container 'pgrep -x indiserver >/dev/null'
check in_container 'test -d /home/pins/.local/share/NINA/Plugins/3.0.0'

has_plugin() { in_container "test -d '/opt/pins-plugins/$1'"; }
if has_plugin ninaAPI; then
  check sh -c 'curl -sf http://127.0.0.1:1888/v2/api/version >/dev/null'
fi
if has_plugin Touch-N-Stars; then
  check sh -c 'curl -sf http://127.0.0.1:5000/ | grep -qi "<html"'
fi
# Touch-N-Stars pages that drive another plugin answer 503 (Night Summary:
# "Installed": false) when that plugin is missing or did not load.
if has_plugin Touch-N-Stars; then
  if has_plugin PolarAlignment; then
    check sh -c 'curl -sf http://127.0.0.1:5000/api/tppa/info | grep -q "\"Success\": true"'
  fi
  if has_plugin joko.nina.plugins; then
    check sh -c 'curl -sf http://127.0.0.1:5000/api/hocusfocus/status | grep -q "\"Success\": true"'
  fi
  if has_plugin NINA.Plugin.NightSummary; then
    check sh -c 'curl -sf http://127.0.0.1:5000/api/nightsummary/status | grep -q "\"Installed\": true"'
  fi
fi

# Every bundled plugin must have loaded; a plugin whose composition fails is
# logged as "Failed to load plugin" and skipped.
latest_log='$(ls -t /home/pins/.local/share/NINA/Logs/*.log | head -n 1)'
plugins_expected="$(in_container 'ls /opt/pins-plugins | wc -l')"
loaded=0
for _ in $(seq 1 30); do
  loaded="$(in_container "grep -c 'Successfully loaded plugin' $latest_log || true")"
  [ "${loaded:-0}" -ge "$plugins_expected" ] && break
  sleep 2
done
check [ "${loaded:-0}" -ge "$plugins_expected" ]
check in_container "! grep -q 'Failed to load plugin' $latest_log"

if in_container 'test -x /usr/bin/supervisorctl' 2>/dev/null; then
  say "supervisor status:"
  in_container 'supervisorctl status' | sed 's/^/        /' || true
  check in_container 'supervisorctl status pins | grep -q RUNNING'
  check in_container 'supervisorctl status xvfb | grep -q RUNNING'
  if in_container 'supervisorctl status pinsdaemon | grep -q RUNNING' 2>/dev/null; then
    check sh -c 'curl -sf http://127.0.0.1:8000/health | grep -q pinsdaemon'
    check in_container 'runuser -u sysupdate-api -- /usr/bin/systemctl is-active phd2 || [ $? -eq 1 ]'
  fi
  if in_container 'supervisorctl status phd2 | grep -q RUNNING' 2>/dev/null; then
    soft port_open 4400
  fi
fi

# Host power shim (Touch-N-Stars Shutdown/Restart): the pins user may run it
# through sudo, and without the host's D-Bus socket (not mounted here) it must
# refuse with a message instead of doing anything.
check in_container 'out=$(runuser -u pins -- sudo -n /usr/sbin/shutdown -h now 2>&1); [ $? -eq 1 ] && echo "$out" | grep -q "not available"'

if in_container 'test -x /usr/local/bin/astap_cli' 2>/dev/null; then
  check in_container 'astap_cli -h >/dev/null 2>&1 || astap_cli 2>&1 | grep -qi astap'
  check in_container 'test -d /usr/share/astap/data/ && test -w /home/pins/.local/share/astap'
  check in_container 'test -x /usr/local/bin/pins-install-astap-db && test -x /usr/local/bin/pins-download-skymap'
fi
soft in_container 'ls /usr/bin/indi_asi_ccd /usr/bin/indi_qhy_ccd >/dev/null 2>&1'
if in_container 'test -f /opt/pins-data/indi-3rdparty.json' 2>/dev/null; then
  check in_container 'grep -q indi_asi_ccd /home/pins/Documents/INDI/3rdparty.json'
fi

say "recent application log lines with errors (if any):"
in_container 'ls -t /home/pins/.local/share/NINA/Logs/*.log 2>/dev/null | head -n1 | xargs -r grep -i "|ERROR|" | grep -v -E "DllLoader|ChooserVM" | tail -n 20' || true

if [ "$rc" -eq 0 ]; then say "all checks passed"; else say "some checks FAILED"; fi
exit "$rc"
