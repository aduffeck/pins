#!/bin/sh
# Print the Debian packages that provide the shared libraries needed by the ELF
# files below the given paths. Libraries that live below those same paths are
# skipped (they are part of the artifact itself).
#
# Used at image build time to derive the runtime package list of components
# that are compiled from source (INDI, OpenCvSharp, the External bundle), so
# the runtime stage does not hard-code Ubuntu-release-specific package names.
#
# Usage: ldd-packages.sh PATH...
set -eu
. "$(dirname "$0")/common.sh"

[ $# -gt 0 ] || fail "usage: $0 PATH..."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

find "$@" -type f \( -name '*.so' -o -name '*.so.*' -o -perm -u+x \) 2>/dev/null > "$tmp/candidates" || true

: > "$tmp/libs"
while IFS= read -r file; do
  is_elf "$file" || continue
  ldd "$file" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' >> "$tmp/libs"
done < "$tmp/candidates"

for p in "$@"; do
  realpath -m "$p"
done > "$tmp/roots"

sort -u "$tmp/libs" | while IFS= read -r lib; do
  real="$(realpath -e "$lib" 2>/dev/null)" || continue
  skip=0
  while IFS= read -r root; do
    case "$real" in
      "$root"/*) skip=1 ;;
    esac
  done < "$tmp/roots"
  [ "$skip" -eq 0 ] || continue
  # "pkg:arch: /path" (possibly "pkgA, pkgB: /path"); ignore diversion notes.
  dpkg -S "$real" 2>/dev/null | grep ': /' | cut -d: -f1 | tr ',' '\n' | sed 's/^ *//; s/:[a-z0-9]*$//'
done | sort -u
