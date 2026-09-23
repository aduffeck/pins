#!/bin/sh
# Build the selected pins plugins against the freshly built core and stage each
# one as it would be installed under ~/.local/share/NINA/Plugins/<api>/<Folder>.
# Mirrors the plugin steps of the CI packaging workflow.
#
# Usage: build-plugins.sh CORE_DIR OUTPUT_DIR "key key ..."
# Env:   BUILD_CONFIGURATION (Release), TARGETARCH,
#        FRONTEND_DIST (built Touch-N-Stars web app, default /frontend-dist)
set -eu
. "$(dirname "$0")/common.sh"

core="${1:?usage: $0 CORE_DIR OUTPUT_DIR \"keys\"}"
out="${2:?usage: $0 CORE_DIR OUTPUT_DIR \"keys\"}"
keys="${3:-}"
rid="$(target_rid)"
cfg="${BUILD_CONFIGURATION:-Release}"
frontend_dist="${FRONTEND_DIST:-/frontend-dist}"
core_files="$(dirname "$core")/core-files.txt"
tfm=net10.0

[ -f "$core_files" ] || fail "core file list not found: $core_files (run build-core.sh first)"
rm -rf "$out"
mkdir -p "$out"

# key -> "repo|branch|checkout dir|project (relative to checkout dir)|install folder|flags"
plugin_spec() {
  case "$1" in
    ninaapi)        echo "https://github.com/nitr57/ninaAPI||ninaAPI|ninaAPI/ninaAPI.csproj|ninaAPI|" ;;
    touch-n-stars)  echo "https://github.com/nitr57/N.I.N.A-Plugin-for-Touch-N-Stars|develop|Touch-N-Stars|Touch-N-Stars/Touch-N-Stars.csproj|Touch-N-Stars|frontend" ;;
    joko)           echo "https://github.com/nitr57/joko.nina.plugins||joko.nina.plugins|Joko.NINA.Plugins/Joko.NINA.Plugins.HocusFocus/Joko.NINA.Plugins.HocusFocus.csproj|joko.nina.plugins|" ;;
    livestack)      echo "https://github.com/nitr57/nina.plugin.livestack||LiveStack|nina.plugin.livestack.csproj|LiveStack|" ;;
    polaralignment) echo "https://github.com/nitr57/nina.plugin.polaralignment||PolarAlignment|PolarAlignment/NINA.Plugins.PolarAlignment.csproj|PolarAlignment|" ;;
    nightsummary)   echo "https://github.com/nitr57/nina.plugin.nightsummary||nina.plugin.nightsummary|NINA.Plugin.NightSummary/NINA.Plugin.NightSummary.csproj|NINA.Plugin.NightSummary|" ;;
    orbuculum)      echo "https://github.com/nitr57/nina.plugin.orbuculum||nina.plugin.orbuculum|Orbuculum/Orbuculum.csproj|Orbuculum|" ;;
    phd2tools)      echo "https://github.com/nitr57/nina.plugin.phd2tools||nina.plugin.phd2tools|nina.plugin.phd2tools.csproj|Phd2 Tools|" ;;
    # Native guider (private repo): build it from a local checkout via the local-plugins context
    # (NINA.Plugins/pins-guider), e.g. BUILD_PLUGINS="... pins-guider".
    pins-guider)    echo "https://github.com/aduffeck/pins-guider|main|pins-guider|src/PinsGuider.Plugin/PinsGuider.Plugin.csproj|PinsNativeGuider|" ;;
    tenmicron)      echo "https://github.com/nitr57/NINA.Joko.Plugin.TenMicron||NINA.Joko.Plugin.TenMicron|NINA.Joko.Plugin.TenMicron/NINA.Joko.Plugin.TenMicron.csproj|NINA.Joko.Plugin.TenMicron|java" ;;
    *) return 1 ;;
  esac
}

ensure_java() {
  if ! command -v java >/dev/null 2>&1; then
    log "Installing Java runtime (required by the TenMicron plugin build)"
    apt-get update
    apt-get install -y --no-install-recommends default-jre-headless
    rm -rf /var/lib/apt/lists/*
  fi
  JavaPath="$(command -v java)"
  export JavaPath
}

# Plugin sources are cloned, so a plain build is reproducible. A checkout passed
# through the named build context `local-plugins` (mounted at $local_plugins)
# replaces the clone of the plugin with the same checkout directory name.
local_plugins="${LOCAL_PLUGINS_DIR:-/local-plugins}"

ensure_source() {
  dir="$1" repo="$2" branch="$3" checkout="$4"
  rm -rf "$dir"
  mkdir -p "$(dirname "$dir")"
  if find "$local_plugins/$checkout" -name '*.csproj' 2>/dev/null | grep -q .; then
    log "Using local plugin sources from the local-plugins build context: $checkout"
    cp -a "$local_plugins/$checkout" "$dir"
    # Build output of the host must not leak into the image build.
    find "$dir" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +
    return
  fi
  if [ -n "$branch" ]; then
    git clone --depth 1 --branch "$branch" --single-branch "$repo" "$dir"
  else
    git clone --depth 1 "$repo" "$dir"
  fi
}

build_plugin() {
  key="$1"
  spec="$(plugin_spec "$key")" || fail "Unknown plugin key: $key"
  repo="$(echo "$spec" | cut -d'|' -f1)"
  branch="$(echo "$spec" | cut -d'|' -f2)"
  checkout="$(echo "$spec" | cut -d'|' -f3)"
  project_rel="$(echo "$spec" | cut -d'|' -f4)"
  folder="$(echo "$spec" | cut -d'|' -f5)"
  flags="$(echo "$spec" | cut -d'|' -f6)"

  dir="NINA.Plugins/$checkout"
  project="$dir/$project_rel"
  plugin_dir="$(dirname "$project")"

  log "=== Plugin $key -> $folder ==="
  ensure_source "$dir" "$repo" "$branch" "$checkout"
  [ -f "$project" ] || fail "Project not found: $project"

  case "$flags" in
    *frontend*)
      [ -d "$frontend_dist" ] && [ -n "$(ls -A "$frontend_dist")" ] || fail "Touch-N-Stars web app not built ($frontend_dist is empty)"
      rm -rf "$plugin_dir/app"
      cp -a "$frontend_dist" "$plugin_dir/app"
      ;;
  esac
  case "$flags" in
    *java*) ensure_java ;;
  esac

  dotnet restore "$project" -r "$rid"
  dotnet build "$project" -c "$cfg" -f "$tfm" -r "$rid" --no-restore \
    -p:DisableImplicitSystemDrawingReference=true \
    -p:Platform=AnyCPU \
    -p:PlatformTarget=AnyCPU \
    -p:SatelliteResourceLanguages=en-US

  tfm_dir="$plugin_dir/bin/$cfg/$tfm/$rid"
  if [ ! -d "$tfm_dir" ]; then
    tfm_dir="$(find "$plugin_dir/bin/$cfg" -maxdepth 1 -type d -name 'net*' | head -n 1)"
    [ -n "$tfm_dir" ] || fail "Build output not found under $plugin_dir/bin/$cfg"
  fi

  dest="$out/$folder"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "$tfm_dir/." "$dest/"

  # Drop everything that is part of the core payload (NINA assemblies, runtime
  # bits); the plugin loader resolves those from the application directory.
  while IFS= read -r rel; do
    rm -f "$dest/$rel"
  done < "$core_files"
  find "$dest" -mindepth 1 -maxdepth 1 -type d \( -name '??-??' -o -name '??' \) -exec rm -rf {} +
  find "$dest" -type d -empty -delete
  mkdir -p "$dest"

  if [ -d "$plugin_dir/extra-libs" ]; then
    find "$plugin_dir/extra-libs" -maxdepth 1 -type f -name '*.dll' -exec cp {} "$dest/" \;
  fi
  if [ -d "$plugin_dir/app" ]; then
    rm -rf "$dest/app"
    cp -a "$plugin_dir/app" "$dest/app"
  fi

  # Content stamp; the entrypoint only re-installs a bundled plugin when it changed.
  (cd "$dest" && find . -type f -printf '%p %s\n' | sort | sha256sum | cut -d' ' -f1) > "$dest/.pins-bundle"

  log "Staged $folder: $(du -sh "$dest" | cut -f1)"
}

if [ -z "$keys" ] || [ "$keys" = "none" ]; then
  log "No plugins requested"
  exit 0
fi

for key in $keys; do
  build_plugin "$key"
done

log "Plugins staged under $out:"
ls -1 "$out" | sed 's/^/  /'
