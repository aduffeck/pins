#!/bin/sh
# Fail when any ELF file below the given paths has an unresolved shared library
# dependency. Run in the runtime image after all packages are installed.
#
# Usage: check-native-deps.sh PATH...
set -eu
. "$(dirname "$0")/common.sh"

[ $# -gt 0 ] || fail "usage: $0 PATH..."

# Optional dependencies that are allowed to be missing:
#   liblttng-ust: LTTng tracing provider shipped with the .NET runtime.
allow='liblttng-ust'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

find "$@" -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null > "$tmp/candidates" || true

: > "$tmp/missing"
while IFS= read -r file; do
  is_elf "$file" || continue
  ldd "$file" 2>/dev/null | grep 'not found' | sed "s|^|$file: |" >> "$tmp/missing" || true
done < "$tmp/candidates"

grep -v -E "$allow" "$tmp/missing" > "$tmp/relevant" || true
if [ -s "$tmp/relevant" ]; then
  log "Unresolved native dependencies:"
  cat "$tmp/relevant" >&2
  fail "native dependency check failed"
fi

log "native dependency check passed ($(wc -l < "$tmp/candidates") files scanned)"
