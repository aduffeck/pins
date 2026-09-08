#!/bin/sh
# Host power control shim for the pins container. Installed as
# /usr/sbin/shutdown, /usr/sbin/poweroff and /usr/sbin/reboot in place of the
# systemd symlinks (dpkg-divert, see the Dockerfile).
#
# There is no systemd in the container, so the Touch-N-Stars "Shutdown" and
# "Restart" buttons, which run `sudo shutdown -h now` / `sudo shutdown -r now`
# in the pins process, cannot act on the container. This shim asks the host's
# logind over the host's system D-Bus socket to power off or reboot the
# machine instead, the way `shutdown` on a Raspberry Pi installation does.
#
# Before the host goes down, pins and PHD2 are stopped through supervisord so
# that they write their settings (some are only saved at exit, and the Docker
# daemon's own shutdown timeout would cut a 60 s clean stop short). The stop
# and the logind call run detached; the command itself returns at once, like
# `shutdown now` does, so the HTTP request that triggered it gets its reply.
#
# Requirements (see docker/README.md, "Host shutdown and reboot"):
#   * the host socket mounted into the container:
#       -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro
#   * a privileged container (Docker's default AppArmor profile blocks D-Bus)
#   * root: the pins user is granted `shutdown -h now` and `shutdown -r now`
#     through sudo (docker/sudoers-pins)
#
# Options: -h, -P, --poweroff (power off; the default when invoked as
# `shutdown`), -r, --reboot (reboot), `now` or `+0` as the time argument,
# --dry-run (check the preconditions and print what would happen, without
# stopping anything). Delayed shutdowns, cancelling and wall messages are not
# supported.
set -eu

socket=/run/dbus/system_bus_socket
dest=org.freedesktop.login1
path=/org/freedesktop/login1
iface=org.freedesktop.login1.Manager
me="$(basename "$0")"

fail() { echo "$me: $*" >&2; exit 1; }

case "$me" in
  reboot)   method=Reboot ;;
  *)        method=PowerOff ;;
esac
dry_run=0
for arg in "$@"; do
  case "$arg" in
    -h|-P|--poweroff|--halt|-H) method=PowerOff ;;
    -r|--reboot)                method=Reboot ;;
    now|+0)                     ;;
    --dry-run)                  dry_run=1 ;;
    --no-wall)                  ;;
    -c|--help|-k|--show)        fail "'$arg' is not supported inside the pins container" ;;
    -*)                         fail "unknown option '$arg'" ;;
    *)                          fail "only 'now' is supported as the time argument inside the pins container" ;;
  esac
done

case "$method" in
  Reboot)   what="reboot";    probe=CanReboot ;;
  PowerOff) what="power off"; probe=CanPowerOff ;;
esac

[ "$(id -u)" -eq 0 ] || fail "must run as root (the pins user has it through sudo)"

[ -S "$socket" ] || fail "host power control is not available: $socket is not mounted. \
Run the container with -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro \
(compose: the volumes: entry in docker-compose.yml) and --privileged; see docker/README.md."

# Ask logind whether this caller may do it: also catches a missing logind on
# the host, AppArmor confinement (unprivileged container) and polkit refusing
# a non-root caller (user namespace remapping).
if ! answer="$(busctl call "$dest" "$path" "$iface" "$probe" 2>&1)"; then
  case "$answer" in
    *"Access denied"*|*AppArmor*) answer="$answer (D-Bus access is blocked; the container must run with --privileged or apparmor=unconfined)" ;;
  esac
  fail "host power control is not available: $answer"
fi
answer="${answer#s \"}"; answer="${answer%\"}"
[ "$answer" = "yes" ] || fail "the host's logind does not allow this container to $what the host (answer: $answer)"

if [ "$dry_run" -eq 1 ]; then
  echo "$me: would stop pins and PHD2, then $what the host (logind $method)"
  exit 0
fi

# Detached: stop the services cleanly, then ask logind. Standard streams go to
# the container log (supervisord's stdout, PID 1), never to the caller's pipe,
# which the Touch-N-Stars plugin reads until it closes.
log=/proc/1/fd/1
[ -w "$log" ] || log=/dev/null
setsid sh -c '
  echo "[pins-power] stopping pins and PHD2 before asking the host to '"$what"'"
  if [ -S /run/supervisor.sock ]; then
    supervisorctl stop pins phd2 || echo "[pins-power] warning: could not stop the services cleanly"
  else
    echo "[pins-power] supervisord is not running; services are not stopped separately"
  fi
  echo "[pins-power] asking the host (logind) to '"$what"'"
  busctl call '"$dest"' '"$path"' '"$iface"' '"$method"' b false \
    || echo "[pins-power] logind call failed"
' >"$log" 2>&1 </dev/null &

echo "$me: stopping pins and PHD2, then asking the host to $what"
exit 0
