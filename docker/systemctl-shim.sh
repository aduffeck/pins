#!/bin/sh
# systemctl compatibility shim for the pins container.
#
# There is no systemd inside the container. pinsdaemon manages PHD2 through
# `systemctl ... phd2`; those calls are mapped onto supervisord here. Any other
# unit or verb is reported as unsupported.
set -eu

flag_dir=/run/pins
flag="$flag_dir/phd2.enabled"

case "$*" in
  "is-active phd2")
    supervisorctl status phd2 | grep -q RUNNING ;;
  "is-enabled phd2")
    [ -f "$flag" ] ;;
  "start phd2")
    supervisorctl start phd2 >/dev/null ;;
  "stop phd2")
    supervisorctl stop phd2 >/dev/null ;;
  "restart phd2")
    supervisorctl restart phd2 >/dev/null ;;
  "enable phd2")
    mkdir -p "$flag_dir" && touch "$flag" ;;
  "enable --now phd2")
    mkdir -p "$flag_dir" && touch "$flag" && supervisorctl start phd2 >/dev/null ;;
  "disable phd2")
    rm -f "$flag" ;;
  "disable --now phd2")
    rm -f "$flag" && supervisorctl stop phd2 >/dev/null ;;
  "daemon-reload")
    ;;
  *)
    echo "systemctl: '$*' is not supported inside the pins container" >&2
    exit 1 ;;
esac
