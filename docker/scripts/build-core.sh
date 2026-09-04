#!/bin/sh
# Restore, build and publish the pins core application for the image platform
# and stage it in the layout used by the Debian package (see BUILD_PINS.md and
# build-and-install-pins-x64.sh).
#
# Usage: build-core.sh OUTPUT_DIR
# Env:   BUILD_CONFIGURATION (Release), TARGETARCH,
#        OPENCVSHARP_EXTERN (path to a libOpenCvSharpExtern.so built for this image)
set -eu
. "$(dirname "$0")/common.sh"

out="${1:?usage: $0 OUTPUT_DIR}"
rid="$(target_rid)"
cfg="${BUILD_CONFIGURATION:-Release}"
extern="${OPENCVSHARP_EXTERN:-/opt/opencvsharp/libOpenCvSharpExtern.so}"

[ -f CommonAssemblyInfo.cs ] || fail "run from the repository root"
[ -d NINA/External/"$rid" ] || fail "NINA/External/$rid missing; the external stage must run first"

log "Restoring for $rid"
dotnet restore NINA/NINA.csproj -r "$rid"
dotnet restore System.Windows.Compat/System.Windows.Compat.csproj

log "Building System.Windows.Compat"
dotnet build System.Windows.Compat/System.Windows.Compat.csproj -c "$cfg" --no-restore

log "Building NINA ($cfg, $rid)"
dotnet build NINA/NINA.csproj -c "$cfg" -r "$rid" --no-restore

log "Publishing to $out"
rm -rf "$out"
dotnet publish NINA/NINA.csproj -c "$cfg" -r "$rid" --no-build -o "$out"

log "Adding External bundle"
mkdir -p "$out/External"
cp -a NINA/External/. "$out/External/"

compat_dll="System.Windows.Compat/bin/$cfg/net10.0/System.Windows.dll"
[ -f "$compat_dll" ] || fail "Compat build missing at $compat_dll"
cp -f "$compat_dll" "$out/System.Windows.dll"

# OpenCvSharp native library: prefer the one compiled in this image build (it
# links against this Ubuntu release); the NuGet runtime package is only a
# fallback and is built for older Ubuntu releases.
if [ -f "$extern" ]; then
  log "Using OpenCvSharpExtern from $extern"
  cp -f "$extern" "$out/libOpenCvSharpExtern.so"
elif [ -f "$out/libOpenCvSharpExtern.so" ]; then
  log "Using OpenCvSharpExtern from the NuGet runtime package"
else
  fail "libOpenCvSharpExtern.so not available for $rid"
fi
chmod 755 "$out/libOpenCvSharpExtern.so"
cp -f "$out/libOpenCvSharpExtern.so" "$out/OpenCvSharpExtern.so"
mkdir -p "$out/External/$rid"
cp -f "$out/libOpenCvSharpExtern.so" "$out/External/$rid/libOpenCvSharpExtern.so"

echo "${PINS_INSTALL_DIRECTORY:-/opt/pins}" > "$out/.install_path"

# File list of the core payload; plugin packaging strips these from plugin output.
(cd "$out" && find . -type f -printf '%P\n' | sort) > "$(dirname "$out")/core-files.txt"

log "Core payload: $(du -sh "$out" | cut -f1)"
