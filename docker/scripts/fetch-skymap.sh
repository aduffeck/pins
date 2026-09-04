#!/bin/sh
# Download and unpack the N.I.N.A. offline sky map cache (Framing Assistant /
# Sky Atlas images) into the pins data directory. Inside the container this is
# available as `pins-download-skymap`; the cache lands on the data volume.
#
# Usage: fetch-skymap.sh [DATA_DIR]   (default: $HOME/.local/share/NINA)
# Env:   SKYMAP_CACHE_URL
set -eu

data_dir="${1:-${HOME:-/home/pins}/.local/share/NINA}"
url="${SKYMAP_CACHE_URL:-https://nighttime-imaging.eu/downloads/Setup/Releases/FramingAssistantCache_Full.zip}"
dest="$data_dir/FramingAssistantCache"

mkdir -p "$data_dir"
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

echo "Sky map cache ready: $(du -sh "$dest" | cut -f1), $(find "$dest" -type f | wc -l) files in $dest"
