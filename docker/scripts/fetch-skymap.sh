#!/bin/sh
# Download and unpack the N.I.N.A. offline sky map cache (Framing Assistant /
# Sky Atlas images) into the pins data directory. Inside the container this is
# available as `pins-download-skymap`; the cache lands on the data volume.
#
# Started through `docker exec` the script runs as root; the cache is then
# handed to the pins user, which has to write the cache index and add images
# to it.
#
# Usage: fetch-skymap.sh [DATA_DIR]   (default: the pins user's
#        ~/.local/share/NINA, independent of the caller's $HOME)
# Env:   SKYMAP_CACHE_URL
#        PINS_DATA_OWNER  user whose data directory is used and who owns the
#                         cache when run as root (pins)
set -eu

owner="${PINS_DATA_OWNER:-pins}"
url="${SKYMAP_CACHE_URL:-https://nighttime-imaging.eu/downloads/Setup/Releases/FramingAssistantCache_Full.zip}"
if [ $# -gt 0 ]; then
  data_dir="$1"
else
  # The pins user's home from passwd, not $HOME: a login shell or `su -` in
  # the container sets HOME=/root, and a cache there is not on the volume.
  owner_home="$(getent passwd "$owner" 2>/dev/null | cut -d: -f6)"
  data_dir="${owner_home:-${HOME:-/home/pins}}/.local/share/NINA"
fi
dest="$data_dir/FramingAssistantCache"

mkdir -p "$data_dir"
echo "Sky map cache destination: $dest"

# In a container, a destination on the root filesystem is lost when the
# container is re-created (and invisible to pins if it is not its data dir).
if [ -f /.dockerenv ] && ! awk -v p="$data_dir/" '$2 != "/" && index(p, $2 "/") == 1 { f = 1 } END { exit !f }' /proc/mounts; then
  echo "WARNING: $data_dir is not on a mounted volume; the cache will not survive re-creating the container" >&2
fi

# The zip and its unpacked content coexist for a moment.
free_kb="$(df -Pk "$data_dir" | awk 'NR == 2 { print $4 }')"
if [ -n "$free_kb" ] && [ "$free_kb" -lt 8000000 ]; then
  echo "WARNING: only $((free_kb / 1024)) MB free on $data_dir; about 8 GB are needed while unpacking" >&2
fi
tmp="$(mktemp -d -p "$data_dir" .skymap-download.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading sky map cache from $url (about 3.5 GB)..."
curl -fL --progress-bar --retry 5 --retry-delay 10 -C - -o "$tmp/cache.zip" "$url"
echo "Unpacking..."
unzip -q "$tmp/cache.zip" -d "$tmp/unzipped"
rm -f "$tmp/cache.zip"

if [ -L "$dest" ] && [ ! -e "$dest" ]; then
  rm -f "$dest"
fi
mkdir -p "$dest"
if [ -d "$tmp/unzipped/FramingAssistantCache" ]; then
  src="$tmp/unzipped/FramingAssistantCache"
elif [ -d "$tmp/unzipped/framingassistantcache" ]; then
  src="$tmp/unzipped/framingassistantcache"
else
  src="$tmp/unzipped"
fi
cp -a "$src/." "$dest/"

# Files unpacked by root would be read-only for pins: it could still render
# the cached images, but not update the index or add images of its own.
if [ "$(id -u)" -eq 0 ] && id "$owner" >/dev/null 2>&1; then
  chown -R "$owner:$(id -gn "$owner")" "$dest"
fi

echo "Sky map cache ready: $(du -sh "$dest" | cut -f1), $(find "$dest" -type f | wc -l) files in $dest"
