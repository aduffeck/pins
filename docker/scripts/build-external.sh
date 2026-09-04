#!/bin/sh
# Assemble the NINA/External native bundle for the image platform:
#   * vendor SDK libraries + JPLEPH from the pins.external repository (git-lfs)
#   * NOVAS (libnovas_c.so, cio_ra.bin) and SOFA (libsofa_c.so) rebuilt from
#     the sources in this repository, matching the CI packaging workflow.
#
# Usage: build-external.sh OUTPUT_DIR
# Env:   PINS_EXTERNAL_REPO, PINS_EXTERNAL_BRANCH, JPLEPH_URL, TARGETARCH
set -eu
. "$(dirname "$0")/common.sh"

out="${1:?usage: $0 OUTPUT_DIR}"
rid="$(target_rid)"
repo="${PINS_EXTERNAL_REPO:-https://github.com/nitr57/pins.external}"
branch="${PINS_EXTERNAL_BRANCH:-main}"
jpleph_url="${JPLEPH_URL:-https://github.com/isbeorn/nina.external/raw/refs/heads/master/JPLEPH}"

log "Cloning External bundle $repo@$branch for $rid"
rm -rf "$out"
git lfs install --skip-repo
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "$branch" "$repo" "$out"
(
  cd "$out"
  git lfs pull --include "$rid/**,JPLEPH,LICENSE.txt"
)

log "Downloading JPLEPH ephemeris"
curl -fsSL --retry 3 --retry-delay 5 -o "$out/JPLEPH" "$jpleph_url"

rm -rf "$out/.git" "$out/.gitignore" "$out/.gitattributes"
for dir in "$out"/linux-*; do
  [ -d "$dir" ] || continue
  [ "$(basename "$dir")" = "$rid" ] || rm -rf "$dir"
done
[ -d "$out/$rid" ] || fail "$out/$rid not found in External bundle"

# NOVAS: shared library from the in-repo sources. cio_ra.bin is generated from
# CIO_RA.TXT, which is stored in git-lfs; when the build context only holds the
# pointer file, the copy shipped in pins.external is kept instead.
log "Building NOVAS"
make -C NOVAS31 clean >/dev/null 2>&1 || true
make -C NOVAS31 libnovas_c.so
mkdir -p "$out/$rid/NOVAS"
cp -f NOVAS31/libnovas_c.so "$out/$rid/NOVAS/libnovas_c.so"
if is_lfs_pointer NOVAS31/NOVAS31/CIO_RA.TXT; then
  log "NOVAS31/NOVAS31/CIO_RA.TXT is a git-lfs pointer; keeping cio_ra.bin from pins.external"
  [ -f "$out/$rid/NOVAS/cio_ra.bin" ] || fail "cio_ra.bin missing from External bundle"
else
  make -C NOVAS31 cio-file
  cp -f NOVAS31/cio_ra.bin "$out/$rid/NOVAS/cio_ra.bin"
fi

# SOFA: the makefile builds a static archive; link the shared object explicitly
# (same steps as the CI workflow).
log "Building SOFA"
(
  cd SOFA/SOFA/src
  rm -f ./*.o ./*.pic.o libsofa_c.so
  for src in ./*.c; do
    [ "$(basename "$src")" = "t_sofa_c.c" ] && continue
    gcc -fPIC -O2 -c "$src"
  done
  gcc -shared -o libsofa_c.so ./*.o -lm
)
mkdir -p "$out/$rid/SOFA"
cp -f SOFA/SOFA/src/libsofa_c.so "$out/$rid/SOFA/libsofa_c.so"

# Everything under the platform folder must be real content, not LFS pointers.
find "$out" -type f | while IFS= read -r f; do
  if is_lfs_pointer "$f"; then
    fail "git-lfs pointer left in External bundle: $f"
  fi
done

[ -f "$out/JPLEPH" ] || fail "JPLEPH missing"
log "External bundle ready:"
find "$out" -type f | sort | sed 's/^/  /'
