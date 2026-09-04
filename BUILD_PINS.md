# PINS build instructions

This document describes how to build the PINS Debian package (Raspberry Pi `linux-arm64`) and optional plugin Debian packages from this repository.

> Notes
>
> - These steps are intended for Ubuntu (or Debian-like). On Windows, use WSL2 (Ubuntu) or a Linux machine.
> - Commands below are written for `bash`.

---

## Prerequisites

### OS

- Ubuntu (or Debian-like) recommended.

### Tools

Install required system tools:

```bash
sudo apt-get update
sudo apt-get install -y \
  git git-lfs \
  curl unzip rsync \
  ca-certificates \
  dpkg-dev
```

Install required SDKs:

- .NET SDK `10.0.x`
- Node.js `22.x`

How you install those (apt, asdf, mise, official installers) is up to you.

Verify:

```bash
dotnet --info
node --version
npm --version
```

---

## Runtime prerequisites (recommended)

These steps are not required to *build* the `.deb`, but are commonly required for a usable system after you install it on the Raspberry Pi.

### Offline Sky Map Cache (Framing Assistant cache)

PINS/N.I.N.A uses an “Offline Sky Map Cache” for the Framing Assistant / Sky Atlas images.

Default cache directory (because the systemd service runs as user `pi`):

- `/home/pi/.local/share/NINA/FramingAssistantCache`

You can change this path in the application settings, but if you don’t, this is where it will look.

Download and install the full cache:

```bash
set -euo pipefail

cache_url="https://nighttime-imaging.eu/downloads/Setup/Releases/FramingAssistantCache_Full.zip"
cache_root="/home/pi/.local/share/NINA"
cache_dir="$cache_root/FramingAssistantCache"

tmp_dir="$(mktemp -d)"
zip_path="$tmp_dir/FramingAssistantCache_Full.zip"
unzip_dir="$tmp_dir/unzipped"

mkdir -p "$cache_root"

echo "Downloading FramingAssistant cache: $cache_url"
curl -L --fail --retry 3 --retry-delay 5 -o "$zip_path" "$cache_url"

rm -rf "$cache_dir"
mkdir -p "$cache_dir"
unzip -q "$zip_path" -d "$unzip_dir"

# The zip contents may or may not include a single top-level folder.
# Try the most common layouts and fall back to copying everything.
if [ -d "$unzip_dir/FramingAssistantCache" ]; then
  rsync -a "$unzip_dir/FramingAssistantCache/" "$cache_dir/"
elif [ -d "$unzip_dir/framingassistantcache" ]; then
  rsync -a "$unzip_dir/framingassistantcache/" "$cache_dir/"
else
  rsync -a "$unzip_dir/" "$cache_dir/"
fi

# Ensure the service user can read it.
sudo chown -R pi:pi "$cache_dir" || true

echo "Installed cache under: $cache_dir"
ls -la "$cache_dir" | head
```

If the sky atlas image is displayed as a black image in clients/plugins, it usually indicates the Offline Sky Map Cache directory is missing or misconfigured.

### ASTAP (plate solver)

PINS can use ASTAP as a plate solver. On Linux it runs ASTAP as an external CLI process.

Recommended target paths (pick one):

- `/usr/local/bin/astap_cli` (commonly used by CLI-only installs)
- `/usr/bin/astap` (often used by distro packages)

#### Option A: Install ASTAP from your distro (if available)

```bash
sudo apt-get update
sudo apt-get install -y astap || true

# Verify it exists (either path can be valid depending on the package)
command -v astap || true
ls -la /usr/bin/astap /usr/local/bin/astap_cli 2>/dev/null || true
```

#### Option B: Manual install (when you have an `astap_cli` binary)

If you have an ARM64-compatible `astap_cli` binary:

```bash
sudo install -m 755 ./astap_cli /usr/local/bin/astap_cli

# Optional: provide a second path some configs expect
sudo ln -sf /usr/local/bin/astap_cli /usr/bin/astap

/usr/local/bin/astap_cli -h || true
```

ASTAP also requires its star database files to be installed (otherwise solves will fail or be unreliable). Install the ASTAP star database(s) according to the ASTAP documentation and ensure ASTAP can find them on your system.

Finally, in the PINS/N.I.N.A plate solver settings, set **ASTAP Location** to the exact path you installed (for example `/usr/local/bin/astap_cli`).

---

## Environment variables

```bash
export BUILD_CONFIGURATION=Release
export TARGET_RUNTIME=linux-arm64
export INSTALL_DIRECTORY=/home/pi/pins
export PUBLISH_DIRECTORY=artifacts/publish
export PACKAGE_ROOT=artifacts/package
export PACKAGE_NAME=pins-linux-arm64
export DEB_ROOT=artifacts/debroot
export DEB_PACKAGE=pins
export DEB_ARCH=arm64

export PLUGINS_INSTALL_BASE=/home/pi/.local/share/NINA/Plugins/3.0.0
export PLUGIN_DEB_BASE=artifacts/plugin-debroot
export PLUGIN_ARTIFACT_DIR=artifacts/plugins
export PLUGIN_MSBUILD_ARGS='-p:DisableImplicitSystemDrawingReference=true'
export PLUGIN_FAILURES_FILE=artifacts/plugin-build-failures.log
```

Choose a local build number to make versions unique:

```bash
export BUILD_NUMBER=1
```

---

## 1) Checkout and submodules

```bash
git lfs install
# If you already cloned the repo, just `cd` into it.
# Otherwise:
# git clone <your repo url> pins
# cd pins

# Update all submodules except `NINA/External` (it is populated from a zip bundle below)
excluded_path="NINA/External"
while read -r _ path; do
  if [ "$path" = "$excluded_path" ]; then
    echo "Skipping submodule $path"
    continue
  fi

  echo "Updating submodule $path"
  if git submodule update --init --recursive --remote "$path"; then
    continue
  fi

  echo "Remote update failed for $path; falling back to pinned commit" >&2
  git submodule update --init --recursive "$path"
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')
```

---

## 2) Populate `NINA/External` from zip bundle

```bash
set -euo pipefail

url="http://cloud.astro-narren.de/public.php/dav/files/7tEAZoEpCMCYyeX/?accept=zip"
tmp_dir="$(mktemp -d)"
zip_path="$tmp_dir/external.zip"
unzip_dir="$tmp_dir/unzipped"

echo "Downloading External bundle from: $url"
curl -L --fail --retry 3 --retry-delay 5 -o "$zip_path" "$url"

rm -rf "NINA/External"
mkdir -p "NINA/External"
unzip -q "$zip_path" -d "$unzip_dir"

if [ ! -d "$unzip_dir/external" ]; then
  echo "Downloaded zip did not contain top-level folder 'external'" >&2
  echo "Top-level entries:" >&2
  (cd "$unzip_dir" && find . -mindepth 1 -maxdepth 2 -print | head -n 50) >&2
  exit 1
fi

rsync -a "$unzip_dir/external/" "NINA/External/"
echo "External bundle extracted into NINA/External"
```

---

## 3) Restore + build + publish `linux-arm64`

```bash
# Restore

dotnet restore NINA/NINA.csproj -r "$TARGET_RUNTIME"
dotnet restore System.Windows.Compat/System.Windows.Compat.csproj

# Build compat shim
dotnet build System.Windows.Compat/System.Windows.Compat.csproj \
  -c "$BUILD_CONFIGURATION" \
  --no-restore

# Build NINA for linux-arm64
dotnet build NINA/NINA.csproj \
  -c "$BUILD_CONFIGURATION" \
  -r "$TARGET_RUNTIME" \
  --no-restore

# Publish payload
publish_root="$PUBLISH_DIRECTORY/$TARGET_RUNTIME"
dotnet publish NINA/NINA.csproj \
  -c "$BUILD_CONFIGURATION" \
  -r "$TARGET_RUNTIME" \
  --no-build \
  -o "$publish_root"
```

---

## 4) Include External bundle + stage `libOpenCvSharpExtern.so`

```bash
set -euo pipefail

publish_root="$PUBLISH_DIRECTORY/$TARGET_RUNTIME"

if [ ! -d "NINA/External" ]; then
  echo "NINA/External not found; native bundle was not populated" >&2
  exit 1
fi

mkdir -p "$publish_root/External"
rsync -a "NINA/External/" "$publish_root/External/"

# Some native libs must also live in the application root (not under External)
opencv_so="$publish_root/External/$TARGET_RUNTIME/libOpenCvSharpExtern.so"
if [ ! -f "$opencv_so" ]; then
  echo "Expected OpenCvSharp native library not found at: $opencv_so" >&2
  exit 1
fi

cp -f "$opencv_so" "$publish_root/OpenCvSharpExtern.so"
chmod 755 "$publish_root/OpenCvSharpExtern.so"
chown pi:pi "$publish_root/OpenCvSharpExtern.so"
```

---

## 5) Stage `/home/pi/pins` layout

```bash
publish_root="$PUBLISH_DIRECTORY/$TARGET_RUNTIME"
rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/pins"
rsync -a "$publish_root/" "$PACKAGE_ROOT/pins/"

echo "$INSTALL_DIRECTORY" > "$PACKAGE_ROOT/pins/.install_path"
```

Replace `System.Windows.dll` with the compat build:

```bash
compat_dll="System.Windows.Compat/bin/$BUILD_CONFIGURATION/net10.0/System.Windows.dll"
target_dir="$PACKAGE_ROOT/pins"

if [ ! -f "$compat_dll" ]; then
  echo "Compat build missing at $compat_dll" >&2
  exit 1
fi

cp -f "$compat_dll" "$target_dir/System.Windows.dll"
```

---

## 6) Build the Debian package

Prepare deb filesystem:

```bash
deb_root="$DEB_ROOT"
install_root="$deb_root/home/pi/pins"
rm -rf "$deb_root"
mkdir -p "$install_root"
rsync -a "$PACKAGE_ROOT/pins/" "$install_root/"
```

Add systemd service:

```bash
service_path="$deb_root/etc/systemd/system/pins.service"
mkdir -p "$(dirname "$service_path")"
cp packaging/systemd/pins.service "$service_path"
chmod 644 "$service_path"
```

Add maintainer scripts:

```bash
control_dir="$deb_root/DEBIAN"
mkdir -p "$control_dir"
cp packaging/debian/postinst "$control_dir/postinst"
cp packaging/debian/prerm "$control_dir/prerm"
chmod 755 "$control_dir/postinst" "$control_dir/prerm"
```

Determine version strings

```bash
# Package version: <AssemblyInformationalVersion>+<build_number>
base_version=$(grep -m1 'AssemblyInformationalVersion' CommonAssemblyInfo.cs | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$base_version" ]; then
  echo "Failed to determine version from CommonAssemblyInfo.cs" >&2
  exit 1
fi
package_version="${base_version}+${BUILD_NUMBER}"

# Release tag format: v<ddmmyyyy>-<build_number>
release_date=$(date +%d%m%Y)
release_version="v${release_date}-${BUILD_NUMBER}"

echo "Base version: $base_version"
echo "Package version: $package_version"
echo "Release tag: $release_version"
```

Build `.deb` (writes the control file, then runs `dpkg-deb --build`):

```bash
installed_size=$(du -sk "$deb_root/home/pi/pins" | cut -f1)
{
  echo "Package: $DEB_PACKAGE"
  echo "Version: $package_version"
  echo "Section: misc"
  echo "Priority: optional"
  echo "Architecture: $DEB_ARCH"
  echo "Maintainer: N.I.N.A. Team"
  echo "Installed-Size: $installed_size"
  echo "Description: Pins build for Raspberry Pi"
} > "$deb_root/DEBIAN/control"

deb_path="artifacts/${DEB_PACKAGE}_${package_version}_${DEB_ARCH}_${release_date}.deb"
dpkg-deb --build "$deb_root" "$deb_path"
sha256sum "$deb_path" > "$deb_path.sha256"

echo "Built: $deb_path"
```

---

## 7) Install on the Pi

Copy the `.deb` to your Raspberry Pi and install:

```bash
sudo dpkg -i pins_*.deb
# If dependencies are missing:
sudo apt-get -f install
```

After installation, you should see:

- `/home/pi/pins/libOpenCvSharpExtern.so` (mode `755`)

---

## Optional: Build plugin Debian packages

This repository can also produce plugin `.deb` packages. Output files are written under:

- `artifacts/plugins/*.deb`

### Prepare plugin workspace

```bash
rm -rf "$PLUGIN_DEB_BASE"
mkdir -p "$PLUGIN_ARTIFACT_DIR"
mkdir -p "$(dirname "$PLUGIN_FAILURES_FILE")"
rm -f "$PLUGIN_FAILURES_FILE"
```

### Common helper (build a plugin deb)

The commands below define a helper function and then build each plugin package.

```bash
set -euo pipefail

build_dotnet_plugin_deb() {
  local project_path="$1"
  local install_folder="$2"
  local deb_package="$3"

  local plugin_dir
  plugin_dir=$(dirname "$project_path")

  local assembly_info="$plugin_dir/Properties/AssemblyInfo.cs"
  if [ ! -f "$assembly_info" ]; then
    assembly_info=$(find "$plugin_dir" -name AssemblyInfo.cs | head -n 1)
  fi
  if [ -z "$assembly_info" ] || [ ! -f "$assembly_info" ]; then
    echo "AssemblyInfo.cs not found for $deb_package" >&2
    return 1
  fi

  local assembly_version_line
  assembly_version_line=$(grep -E 'AssemblyVersion' "$assembly_info" || true)
  local plugin_version
  plugin_version=$(echo "$assembly_version_line" | sed -E 's/.*"([^\"]+)".*/\1/')
  if [ -z "$plugin_version" ]; then
    echo "AssemblyVersion not found in $assembly_info" >&2
    return 1
  fi

  # Make versions unique per local build.
  plugin_version="${plugin_version}+${BUILD_NUMBER}"

  dotnet restore "$project_path"
  dotnet build "$project_path" -c "$BUILD_CONFIGURATION" --no-restore $PLUGIN_MSBUILD_ARGS

  local build_root="$plugin_dir/bin/$BUILD_CONFIGURATION"
  local tfm_dir
  tfm_dir=$(find "$build_root" -maxdepth 1 -type d -name 'net*' | head -n 1)
  if [ -z "$tfm_dir" ]; then
    echo "Could not locate target framework output under $build_root" >&2
    return 1
  fi

  local deb_root="$PLUGIN_DEB_BASE/$deb_package"
  local install_root="$deb_root$PLUGINS_INSTALL_BASE/$install_folder"
  rm -rf "$deb_root"
  mkdir -p "$install_root"
  rsync -a "$tfm_dir/" "$install_root/"

  local extra_libs="$plugin_dir/extra-libs"
  if [ -d "$extra_libs" ]; then
    find "$extra_libs" -maxdepth 1 -type f -name '*.dll' -exec cp {} "$install_root/" \;
  fi

  local app_dir="$plugin_dir/app"
  if [ -d "$app_dir" ]; then
    rm -rf "$install_root/app"
    cp -a "$app_dir" "$install_root/app"
  fi

  local control_dir="$deb_root/DEBIAN"
  mkdir -p "$control_dir"
  local installed_size
  installed_size=$(du -sk "$deb_root$PLUGINS_INSTALL_BASE" | cut -f1)
  {
    echo "Package: $deb_package"
    echo "Version: $plugin_version"
    echo "Section: misc"
    echo "Priority: optional"
    echo "Architecture: $DEB_ARCH"
    echo "Maintainer: N.I.N.A. Team"
    echo "Installed-Size: $installed_size"
    echo "Description: NINA plugin package for $install_folder"
  } > "$control_dir/control"

  local release_date
  release_date=$(date +%d%m%Y)
  local deb_path="$PLUGIN_ARTIFACT_DIR/${deb_package}_${plugin_version}_${DEB_ARCH}_${release_date}.deb"
  dpkg-deb --build "$deb_root" "$deb_path"
  sha256sum "$deb_path" > "$deb_path.sha256"
  echo "Built: $deb_path"
}
```

### Build each plugin package

#### HocusFocus (Joko)

```bash
build_dotnet_plugin_deb \
  "NINA.Plugins/joko.nina.plugins/Joko.NINA.Plugins/Joko.NINA.Plugins.HocusFocus/Joko.NINA.Plugins.HocusFocus.csproj" \
  "joko.nina.plugins" \
  "pins-plugin-joko"
```

#### LiveStack

```bash
build_dotnet_plugin_deb \
  "NINA.Plugins/LiveStack/nina.plugin.livestack.csproj" \
  "LiveStack" \
  "pins-plugin-livestack"
```

#### ninaAPI

```bash
build_dotnet_plugin_deb \
  "NINA.Plugins/ninaAPI/ninaAPI/ninaAPI.csproj" \
  "ninaAPI" \
  "pins-plugin-ninaapi"
```

#### PolarAlignment

```bash
build_dotnet_plugin_deb \
  "NINA.Plugins/PolarAlignment/PolarAlignment/NINA.Plugins.PolarAlignment.csproj" \
  "PolarAlignment" \
  "pins-plugin-polaralignment"
```

#### Touch-N-Stars (includes frontend build)

This plugin requires a frontend build output placed under `NINA.Plugins/Touch-N-Stars/Touch-N-Stars/app` before the .NET build.

```bash
set -euo pipefail

project_path="NINA.Plugins/Touch-N-Stars/Touch-N-Stars/Touch-N-Stars.csproj"
plugin_dir=$(dirname "$project_path")
tmp_dir="$plugin_dir/frontend-build"

rm -rf "$tmp_dir" "$plugin_dir/app"
git clone --branch pins --single-branch https://github.com/Touch-N-Stars/Touch-N-Stars.git "$tmp_dir"
pushd "$tmp_dir" >/dev/null
npm install
npm run build
popd >/dev/null

mv "$tmp_dir/dist" "$plugin_dir/app"

build_dotnet_plugin_deb \
  "$project_path" \
  "Touch-N-Stars" \
  "pins-plugin-touch-n-stars"
```

---

## PINS APT Repository

We host an APT repository for Raspberry Pi (arm64) containing PINS builds, plugins, and dependencies.

### Adding the Repository

1.  **Add the GPG key:**

    ```bash
    curl -fsSL https://repo.touch-n-stars.eu/repository-key.asc | sudo gpg --dearmor -o /usr/share/keyrings/pins-archive-keyring.gpg
    ```

2.  **Add the repository source:**

    ```bash
    echo "deb [arch=arm64 signed-by=/usr/share/keyrings/pins-archive-keyring.gpg] https://repo.touch-n-stars.eu/reprepro trixie main" | sudo tee /etc/apt/sources.list.d/pins.list
    ```

3.  **Update APT:**

    ```bash
    sudo apt-get update
    ```

### Available Packages

You can install these packages using `sudo apt-get install <package_name>`.

| Package Name | Description | Version (Example) |
| :--- | :--- | :--- |
| **PINS Core** | | |
| `pins` | Main PINS application for Raspberry Pi | 3.3.0.1000-nightly |
| `pinsdaemon` | System daemon for updates and management | 1.0.0 |
| **Plugins** | | |
| `pins-plugin-joko` | HocusFocus Plugin | 3.0.0.24 |
| `pins-plugin-livestack` | LiveStack Plugin | 1.0.1.2 |
| `pins-plugin-ninaapi` | ninaAPI Plugin | 2.2.14.1 |
| `pins-plugin-polaralignment` | PolarAlignment Plugin | 2.2.3.4 |
| `pins-plugin-touch-n-stars` | Touch-N-Stars Plugin | 1.2.4.0 |
| **Dependencies / Tools** | | |
| `libindi1` | INDI Shared Library | 2.1.7 |
| `libindi-dev` | INDI Development Files | 2.1.7 |
| `libindi-data` | INDI Data Files | 2.1.7 |
| `indi-bin` | INDI Server and Drivers | 2.1.7 |
| `indi-dbg` | INDI Debug Symbols | 2.1.7 |
| `opencv` | OpenCV Libraries | 4.11.0 |
| `opencv-dbgsym` | OpenCV Debug Symbols | 4.11.0 |
| `opencv-qeng` | OpenCV PI Optimized Build | 4.11.0 |
| `phd2` | PHD2 Guiding | 2.6.13dev8 |
| `astap_cli` | ASTAP Plate Solving (Manual) | `command-line_version_Linux_aarch64` |

### Installing ASTAP CLI

If you need the ASTAP CLI capability:

1.  Download the package:
    [astap_command-line_version_Linux_aarch64.zip](https://sourceforge.net/projects/astap-program/files/linux_installer/astap_command-line_version_Linux_aarch64.zip/download)

2.  Extract and install to path:
    ```bash
    unzip astap_command-line_version_Linux_aarch64.zip
    sudo cp astap_cli /usr/local/bin/
    sudo chmod +x /usr/local/bin/astap_cli
    ```

---

## Docker

A container build of the complete server (core application, External bundle,
OpenCvSharp, INDI and the indi-3rdparty drivers, PHD2, pinsdaemon, ASTAP,
optional plugins; star databases and the sky map cache are downloaded on
demand) is provided by the `Dockerfile` in the repository root:

```bash
docker build --network=host -t pins:local .
docker compose up -d
```

See [`docker/README.md`](docker/README.md) for build arguments, volumes,
ports, hardware access and how it relates to the Debian package build above.
