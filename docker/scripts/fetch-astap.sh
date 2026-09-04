#!/bin/sh
# Download the ASTAP command-line plate solver for the image platform.
# Star databases are not bundled; see install-astap-db.sh (pins-install-astap-db
# inside the container).
#
# Usage: fetch-astap.sh OUTPUT_DIR
# Env:   TARGETARCH
set -eu
. "$(dirname "$0")/common.sh"

out="${1:?usage: $0 OUTPUT_DIR}"
base="https://sourceforge.net/projects/astap-program/files"

case "$(target_rid)" in
  linux-x64) zip="astap_command-line_version_Linux_amd64.zip" ;;
  linux-arm64) zip="astap_command-line_version_Linux_aarch64.zip" ;;
esac

mkdir -p "$out/bin"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "Downloading ASTAP CLI ($zip)"
curl -fsSL --retry 3 --retry-delay 5 -o "$tmp/astap.zip" "$base/linux_installer/$zip/download"
unzip -q "$tmp/astap.zip" -d "$tmp/astap"
cli="$(find "$tmp/astap" -type f -name 'astap_cli' | head -n1)"
[ -n "$cli" ] || fail "astap_cli not found in $zip"
install -m 755 "$cli" "$out/bin/astap_cli"
