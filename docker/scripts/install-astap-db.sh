#!/bin/sh
# Download ASTAP star database(s) into the pins data volume.
#
# ASTAP publishes its databases as Debian packages whose payload lives under
# /opt/astap. In the container /opt/astap and /usr/share/astap/data (the
# directory the CLI searches) point into the data volume, so a database
# installed here survives container re-creation.
#
# Usage: pins-install-astap-db ID [ID ...]      (d05, d20, d50, d80, g05, w08, ...)
# Env:   ASTAP_DATA_DIR (default /home/pins/.local/share/astap)
set -eu

data_dir="${ASTAP_DATA_DIR:-/home/pins/.local/share/astap}"
base="https://sourceforge.net/projects/astap-program/files/star_databases"

[ $# -gt 0 ] || { echo "usage: pins-install-astap-db ID [ID ...]   (for example: d50, d05, d20, g05, w08)" >&2; exit 2; }

mkdir -p "$data_dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for id in "$@"; do
  id="$(echo "$id" | tr 'A-Z' 'a-z')"
  case "$id" in
    w08) file="w08_star_database_mag08_astap.deb" ;;
    *) file="${id}_star_database.deb" ;;
  esac
  echo "Downloading ASTAP star database $id ($file)..."
  curl -fL --progress-bar --retry 3 --retry-delay 5 -o "$tmp/$file" "$base/$file/download"
  rm -rf "$tmp/x"; mkdir -p "$tmp/x"
  dpkg-deb -x "$tmp/$file" "$tmp/x"
  [ -d "$tmp/x/opt/astap" ] || { echo "unexpected package layout in $file" >&2; exit 1; }
  count="$(find "$tmp/x/opt/astap" -type f | wc -l)"
  cp -a "$tmp/x/opt/astap/." "$data_dir/"
  rm -f "$tmp/$file"
  echo "Installed $count files of database $id into $data_dir"
done

echo "ASTAP databases present: $(ls "$data_dir" | sed -E 's/_.*//' | sort -u | tr '\n' ' ')"
