#!/bin/sh
# Shared helpers for the pins Docker build scripts. Sourced, not executed.

log() {
  printf '[pins-docker] %s\n' "$*"
}

fail() {
  printf '[pins-docker] ERROR: %s\n' "$*" >&2
  exit 1
}

# .NET runtime identifier for the image platform. Docker/BuildKit exposes the
# target platform as TARGETARCH; fall back to the build machine otherwise.
target_rid() {
  arch="${TARGETARCH:-}"
  if [ -z "$arch" ]; then
    case "$(uname -m)" in
      x86_64) arch=amd64 ;;
      aarch64 | arm64) arch=arm64 ;;
      *) arch="$(uname -m)" ;;
    esac
  fi
  case "$arch" in
    amd64) echo linux-x64 ;;
    arm64) echo linux-arm64 ;;
    *) fail "Unsupported target architecture: $arch" ;;
  esac
}

# True when the file is an ELF binary (shared object or executable).
is_elf() {
  [ "$(head -c 4 "$1" 2>/dev/null | od -An -c | tr -d ' \n')" = "177ELF" ]
}

# True when the file is a git-lfs pointer instead of real content.
is_lfs_pointer() {
  head -c 40 "$1" 2>/dev/null | grep -q 'git-lfs.github.com/spec'
}
