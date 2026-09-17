# Running pins in Docker

The `Dockerfile` in the repository root builds a self-contained image of the
pins astrophotography server: the headless pins core, INDI with the 3rd-party
vendor drivers, PHD2, pinsdaemon and ASTAP. Star databases and the offline
sky map cache are downloaded on demand into the data volume (see "Downloading
data" below). It is the container equivalent of the full Raspberry Pi
installation described in [`BUILD_PINS.md`](../BUILD_PINS.md) and performed by
`build-and-install-pins-x64.sh`, without the `.deb` packaging, systemd and the
host-wide installs.

## Quick start

```bash
# Build (about 30 minutes on the first run; later runs reuse cached stages)
docker build --network=host -t pins:local .

# Run with persistent data (host directories) and host networking
docker run -d --name pins --network host --stop-timeout 90 \
  -v "$PWD/data/home:/home/pins" -v "$PWD/data/images:/home/pins/Documents/N.I.N.A" \
  pins:local

# or with compose (same layout, plus USB access; see docker-compose.yml)
docker compose build
docker compose up -d
```

Then open `http://<host>:5000` for the Touch-N-Stars web UI. The ninaAPI
endpoint answers on `http://<host>:1888/v2/api/version`, pinsdaemon on
`http://<host>:8000/health`, PHD2's server API on port 4400.

The first build downloads sources and vendor SDKs and compiles OpenCV, INDI
and PHD2; it takes 20-40 minutes on a fast machine. Later builds reuse the
cached stages.

`--network=host` on `docker build` gives the `RUN` steps internet access
through the host's network stack. It is required on hosts where Docker's
default bridge network has no outbound connectivity (the case on the machine
this was developed on) and harmless everywhere else. `docker-compose.yml` sets
it under `build.network`.

## What the image contains

| Component | Source | Notes |
| --- | --- | --- |
| pins core | `NINA/NINA.csproj`, self-contained `linux-x64` (or `linux-arm64`) publish | Installed at `/opt/pins`, started as `/opt/pins/NINA` |
| `System.Windows.dll` | `System.Windows.Compat` | Replaces the framework facade, as in the `.deb` |
| External bundle | `nitr57/pins.external` (git-lfs) + JPLEPH | Vendor SDKs (ASI, ToupTek, Oasis, Nitecrawler, Wanderer) stay in `External/<rid>/`; NOVAS and SOFA are rebuilt from the in-repo sources |
| `libOpenCvSharpExtern.so` | OpenCV 4.11.0 + contrib and OpenCvSharp 4.11.0.20250507, built from source | Static, headless OpenCV; no ffmpeg/gtk dependencies. The NuGet runtime package is linked against Ubuntu 20.04/22.04 libraries and does not load on newer releases |
| INDI | `indilib/indi` v2.1.9, built from source | `indiserver`, `libindidriver`, core drivers and simulators |
| INDI 3rd party | `indilib/indi-3rdparty` v2.1.9, built from source | Vendor libraries (ASI, QHY, ToupTek family, Player One, SVBony, Atik, FLI, SBIG, ...) and their drivers. Drivers whose dependencies are not available on Ubuntu (AHP XC/GT) or that need Raspberry Pi hardware (GPIO, libcamera) are switched off; see `INDI_3RDPARTY_DISABLE` in the Dockerfile |
| PHD2 | `acocalypso/phd2` (pins fork), built from source | Runs on a virtual X display (Xvfb) inside the container; controlled through its server API on port 4400 and by Touch-N-Stars |
| pinsdaemon | `Touch-N-Stars/pinsdaemon` with its Python venv | System management API on port 8000, runs as user `sysupdate-api` |
| ASTAP | Command-line solver from SourceForge | `/usr/local/bin/astap_cli` (the pins default). Star databases are downloaded into the volume with `pins-install-astap-db` |
| Plugins | see below | Bundled under `/opt/pins-plugins` and copied into the plugin folder at container start |
| libgphoto2 | Ubuntu package | DSLR (Canon/Nikon) support through the gphoto2 SDK wrapper |

Touch-N-Stars lists INDI drivers per device type from its built-in defaults
plus the registry `~/Documents/INDI/3rdparty.json`, which pinsdaemon updates
when a driver package is installed on a Raspberry Pi. In the container the
drivers are built in, so the registry is generated from the INDI driver
definitions (`/usr/share/indi/*.xml`) at build time
(`docker/scripts/indi-3rdparty-registry.py`) and merged into the user's
registry at every start (set `PINS_REGISTER_INDI_DRIVERS=0` to skip). Entries
you added or edited are kept. Auxiliary drivers are classified by their label
(flat panels, switches, safety monitors); GPS, guider-port and similar
auxiliary drivers have no device type in pins and are left out.

pinsdaemon's INDI package pages (`/packages/indi3rdparty`) report Debian
packages; the drivers in the image are not packages, so they show as not
installed there, and the install action needs the pins APT repository, which
only provides arm64 builds.

The vendor libraries from indi-3rdparty (for example `libSVBCameraSDK.so`,
`libPlayerOneCamera.so`) also serve the native camera SDK path of pins, which
falls back to the system library search path when a library is not in
`External/`. The Oasis (Astroasis) SDK expects hidapi to be loaded first; the
image ships `libhidapi-hidraw0` with the unversioned library name the pins
loader asks for, so those devices work as well. The same applies to cfitsio
(FITS reading and writing), LibRaw (DSLR raw conversion) and libgphoto2: pins
dlopens `libcfitsio.so`, `libraw.so`, `libgphoto2.so` by those bare names,
which Ubuntu only ships in the `-dev` packages, so the image links them to the
versioned runtime libraries and verifies at build time that each one loads.

The `linux-x64` image adds up to about 2.8 GB of layers: 1 GB runtime
libraries (wxWidgets/GTK, OpenCV, ffmpeg, vendor SDKs), 0.6 GB 3rd-party
drivers, 0.4 GB INDI core, 0.5 GB application payload, 0.2 GB Touch-N-Stars
web app.

## Downloading data

Two large data sets are not part of the image. Both helpers write into the
`/home/pins` volume, so the data survives container re-creation:

```bash
# ASTAP star database(s): d50 (860 MB, the usual choice), d05 (97 MB), d20 (381 MB), d80, g05, w08
docker exec pins pins-install-astap-db d50

# Offline sky map cache for the framing assistant / sky atlas (3.5 GB download)
docker exec pins pins-download-skymap
```

`/opt/astap` and `/usr/share/astap/data` point into the volume, so ASTAP finds
the databases without further configuration and pinsdaemon's own database
installer (`/packages/astap/stardatabases/install`, used by Touch-N-Stars)
stores them in the same place. The sky map cache goes to
`~/.local/share/NINA/FramingAssistantCache`, the path pins uses by default.

`docker exec` runs the helpers as root; both hand the downloaded files to the
`pins` user afterwards, because pins writes the cache index (and adds images
to the cache) and pinsdaemon replaces databases. A cache downloaded with an
earlier image is owned by root and read-only for pins: the cached images
still render, but the index cannot be updated. Fix it once with:

```bash
docker exec pins chown -R pins:pins /home/pins/.local/share/NINA/FramingAssistantCache
```

Touch-N-Stars fetches the target picture through its plugin endpoint
(`/api/targetpic` on port 5000). Whether that picture comes from the cache is
a switch in the web app, "Use NINA cache for the target image" (framing page
under the mosaic controls, and on the mount page next to the target picture).
The switch is stored per browser and is on by default. With it on, the
picture is rendered from the cache only, so a missing or empty cache shows a
black image instead of the online DSS image; with it off, the cache is never
used. The cache is read on every request, so no restart is needed after the
download. pins only finds images listed in the index `CacheInfo.xml`, which
is part of the download and must sit directly in the cache directory. If the
picture stays black after the download, check the switch and the index:

```bash
# 2131 for the full cache; a missing file or a small count means the download
# did not land here or the index was overwritten
docker exec pins sh -c 'grep -c "<Image " /home/pins/.local/share/NINA/FramingAssistantCache/CacheInfo.xml'
```

## Build arguments

| Argument | Default | Purpose |
| --- | --- | --- |
| `UBUNTU_VERSION` | `24.04` | Ubuntu release for the runtime image and the native build stages |
| `BUILD_PLUGINS` | `ninaapi touch-n-stars polaralignment joko livestack nightsummary` | Space-separated plugin keys, or `none` |
| `BUILD_CONFIGURATION` | `Release` | .NET configuration |
| `OPENCV_VERSION` / `OPENCVSHARP_VERSION` | `4.11.0` / `4.11.0.20250507` | Must match the `OpenCvSharp4` package version in `NINA/NINA.csproj` |
| `INDI_VERSION` | `2.1.9` | INDI release tag (without the `v`) |
| `PINS_EXTERNAL_REPO` / `PINS_EXTERNAL_BRANCH` | `nitr57/pins.external` / `main` | Source of the External bundle |
| `TNS_FRONTEND_REPO` / `TNS_FRONTEND_BRANCH` | `Touch-N-Stars/Touch-N-Stars` / `develop` | Web app built into the Touch-N-Stars plugin |
| `INDI_3RDPARTY_DISABLE` | see Dockerfile | indi-3rdparty `WITH_*` options switched off |
| `PHD2_REPO` / `PHD2_BRANCH` | `acocalypso/phd2` / `master` | PHD2 sources |
| `PINSDAEMON_REPO` / `PINSDAEMON_BRANCH` | `Touch-N-Stars/pinsdaemon` / default branch | pinsdaemon sources |
| `PINS_UID` / `PINS_GID` | `1000` / `1000` | UID/GID of the `pins` user inside the container |
| `EXTRA_PACKAGES` | empty | Additional apt packages for the runtime image |

Example:

```bash
docker build --network=host \
  --build-arg BUILD_PLUGINS="ninaapi touch-n-stars joko polaralignment" \
  --build-arg PINS_UID=$(id -u) --build-arg PINS_GID=$(id -g) \
  -t pins:local .
```

### Plugin keys

| Key | Plugin | Repository |
| --- | --- | --- |
| `ninaapi` | ninaAPI (REST/WebSocket API used by Touch-N-Stars) | `nitr57/ninaAPI` |
| `touch-n-stars` | Touch-N-Stars plugin + web app | `nitr57/N.I.N.A-Plugin-for-Touch-N-Stars` (`develop`) |
| `joko` | HocusFocus | `nitr57/joko.nina.plugins` |
| `livestack` | LiveStack | `nitr57/nina.plugin.livestack` |
| `polaralignment` | Polar Alignment | `nitr57/nina.plugin.polaralignment` |
| `nightsummary` | Night Summary | `nitr57/nina.plugin.nightsummary` |
| `orbuculum` | Orbuculum | `nitr57/nina.plugin.orbuculum` |
| `phd2tools` | PHD2 Tools | `nitr57/nina.plugin.phd2tools` |
| `tenmicron` | 10Micron (installs a JRE in the build stage) | `nitr57/NINA.Joko.Plugin.TenMicron` |

Several Touch-N-Stars pages drive another plugin and only work when that
plugin is in the image, which is why the default set goes beyond the two API
plugins: Three Point Polar Alignment (TPPA) needs `polaralignment`, the
HocusFocus page and the filter offset assistant need `joko`, Live Stack needs
`livestack` and Night Summary needs `nightsummary`. The 10Micron pages need
`tenmicron`, which is not in the default set because it pulls a Java build
into the image; Ground Station has no build key yet. In the container this is
the only way to get a plugin: the package installer Touch-N-Stars offers on a
Raspberry Pi does not work here.

Without the plugin the page's buttons do nothing. The TPPA page unparks the
mount and then stalls, with
`No subscribers found for topic: PolarAlignmentPlugin_DockablePolarAlignmentVM_StartAlignment`
in the log and `GET http://<host>:5000/api/tppa/info` answering 503
"PolarAlignment plugin not loaded"; `/api/hocusfocus/status` answers 503 the
same way, and `/api/nightsummary/status` reports `Installed: false`. The
plugins' view models are created when the plugin loads, not by a window, so
they work in the headless container without any display.

Plugin sources are cloned during the build, like the CI workflow does. A plain
`docker build .` never looks at the submodules under `NINA.Plugins`; they are
excluded from the build context. To build plugins from local checkouts
(unpushed branches, work in progress), pass the directory as the BuildKit named
context `local-plugins`:

```bash
docker build --network=host --build-context local-plugins=NINA.Plugins -t pins:local .
```

Every directory in it that contains a project replaces the clone of the plugin
with the same checkout directory name (`ninaAPI`, `Touch-N-Stars`, `LiveStack`,
...); empty submodule directories are ignored and those plugins are cloned as
usual. Host build output (`bin`, `obj`) is dropped inside the build.

The Touch-N-Stars web app is cloned from `TNS_FRONTEND_REPO` by default. To
build it from a local checkout (unpushed branches, work in progress), pass the
checkout as the BuildKit named context `tns-frontend`:

```bash
docker build --network=host --build-context tns-frontend=../Touch-N-Stars -t pins:local .
```

Both contexts can be combined. With compose, put the paths into a git-ignored
`docker-compose.override.yml` under `services.pins.build.additional_contexts`
(`tns-frontend`, `local-plugins`). The checkout's
`.dockerignore` keeps `node_modules`, `dist` and the native projects out of the
context; `npm install` runs inside the build.
The Pi-hardware plugin `pins.plugin` (PowerBox/MeteoStation SDKs) is not
covered.

## Services and processes

The container runs `supervisord` as PID 1, which starts:

| Program | User | Purpose | Control |
| --- | --- | --- | --- |
| `xvfb` | pins | Virtual X display for PHD2 (`PINS_DISPLAY`, default `:99`) | always on |
| `pins` | pins | The pins server | always on |
| `phd2` | pins | PHD2 on the virtual display, server API on 4400 | `PHD2_AUTOSTART` (default `true`); at runtime through pinsdaemon or `supervisorctl start/stop phd2` |
| `pinsdaemon` | sysupdate-api | Management API on 8000 | `PINSDAEMON_AUTOSTART` (default `true`) |

Environment variables: `PHD2_AUTOSTART`, `PINS_DISPLAY` (with host
networking the X socket name is shared with the host, so the default `:99`
avoids a desktop session on `:0`), `PINSDAEMON_AUTOSTART`,
`PINSDAEMON_API_TOKEN` (bearer token; the default is the token the pinsdaemon
Debian package ships), `PINS_USBFS_MEMORY_MB` (USB transfer buffer the
entrypoint sets on a privileged container, see "USB devices"), `TZ`.

There is no systemd in the container. pinsdaemon manages PHD2 through
`systemctl`, so `/usr/bin/systemctl` is a small shim that maps the `phd2`
service operations onto supervisord (`docker/systemctl-shim.sh`); it is the
only privileged command granted to `sysupdate-api` besides the ASTAP helper
scripts (`docker/sudoers-pinsdaemon`). pinsdaemon endpoints that need the Pi
operating system (system upgrade, Wi-Fi, hotspot, Samba, localisation, time
setting, power/temperature readings, firmware installation) do not work in
the container and return errors; `/health`, PHD2 status/control, the ASTAP
database listing and the plugin/INDI package listings do. The Touch-N-Stars
"Shutdown" and "Restart" buttons act on the host machine through another
shim; see "Host shutdown and reboot".

PHD2 keeps its profiles in `/home/pins/.phd2` (on the volume). Its window is
not visible anywhere; use the Touch-N-Stars PHD2 pages or the server API.
PHD2 is built with its bundled camera SDKs (ZWO and QHY linked in, ToupTek,
SVBony and Player One under `/usr/lib/phd2`), and it can use every camera
through the INDI drivers in the image.

Running a single process instead of the supervisor still works:

```bash
docker run --rm --network host -v "$PWD/data/home:/home/pins" pins:local /opt/pins/NINA
```

## Runtime layout

| Path | Content |
| --- | --- |
| `/opt/pins` | Application (`NINA` executable, `External/`, `.install_path`) |
| `/opt/pins-plugins/<Folder>` | Plugins bundled in the image |
| `/home/pins/.local/share/NINA` | Profiles, logs, database, plugins, sky map cache |
| `/home/pins/.config` | .NET user settings (for example the ninaAPI port) |
| `/home/pins/Documents/N.I.N.A` | Default image output folder |
| `/home/pins/.phd2` | PHD2 profiles and settings |
| `/home/pins/.local/share/NINA/FramingAssistantCache` | Sky map cache (`pins-download-skymap`) |
| `/home/pins/.local/share/astap` | ASTAP star database(s) (`pins-install-astap-db`); `/opt/astap` and `/usr/share/astap/data` link here |
| `/opt/pinsdaemon` | pinsdaemon application and venv |

`/home/pins` is declared as a volume. `docker-compose.yml` keeps it in host
directories: `./data/home` for everything under the home directory and
`./data/images` for the default image folder. Files are owned by the
container's `pins` user (UID 1000 by default; set `PINS_UID`/`PINS_GID` at
build time to match your host user if it differs).

On every start the entrypoint installs the bundled plugins into
`~/.local/share/NINA/Plugins/3.0.0/`. A folder is replaced only when the
bundled plugin changed (image rebuild), so files a plugin keeps in its folder
survive restarts, and plugins you installed yourself are left alone (set
`PINS_SYNC_BUNDLED_PLUGINS=0` to disable). The application data folder maps
to `~/.local/share/NINA` because `Environment.SpecialFolder.LocalApplicationData`
resolves there on Linux.

### Where settings live, and clean shutdown

| What | Path (in the volume) | Written |
| --- | --- | --- |
| Profiles (equipment, imaging, plate solving, ...) | `.local/share/NINA/Profiles/*.profile` | one second after every change |
| Plugin settings (ninaAPI, Touch-N-Stars) and app settings | `.local/share/N.I.N.A._-_Nighttime_Imag/.../user.config` | on shutdown only |
| PHD2 profiles and settings | `.PHDGuidingV2`, `.phd2/` | on normal PHD2 exit and at some settings changes |
| INDI driver configs, ZWO SDK configs | `.indi/`, `.ZWO/` | by the drivers |
| Captured images | `Documents/N.I.N.A` | by pins |

Because two of those are only written at shutdown, the container has to stop
cleanly: pins first disconnects the equipment and then saves; PHD2 is asked
to close through its server API (`docker/pins-phd2.sh`), which flushes its
configuration, instead of being killed by a signal. `docker-compose.yml` sets
`stop_grace_period: 90s` for that; with `docker run`, pass `--stop-timeout 90`
or use `docker stop -t 90`. Killing the container (`docker kill`, a 10 s
default timeout, a power cut) loses the settings changed since the last save.
The Touch-N-Stars "Shutdown" and "Restart" buttons stop pins and PHD2 the
same way before the host goes down (see "Host shutdown and reboot").

Ports: 4782 (core SignalR hubs), 1888 (ninaAPI), 5000 (Touch-N-Stars web UI),
7624 (indiserver), 4400 (PHD2 server API), 8000 (pinsdaemon). Every service
listens on all interfaces, so with `--network host` they are reachable from
the LAN at the host's address (for example `http://<host>:5000`), and the
Touch-N-Stars mDNS advertisement carries the host's LAN address and port, so
the Touch-N-Stars app discovers the container like a Raspberry Pi. Only a
host firewall can block that. With bridge networking publish the ports with
`-p`; mDNS discovery then does not work.

## Hardware access

The services run as the unprivileged user `pins`. USB equipment needs two
things: the device nodes must be visible in the container, and the user must
be allowed to open them.

```bash
docker run -d --name pins --network host --stop-timeout 90 \
  -v "$PWD/data/home:/home/pins" -v "$PWD/data/images:/home/pins/Documents/N.I.N.A" \
  --privileged -v /dev/bus/usb:/dev/bus/usb \
  pins:local
```

- Bind-mount `/dev/bus/usb` (`-v`, or `volumes:` in compose) rather than
  passing it with `--device`: a `--device` entry only copies the nodes that
  exist when the container is created, so a camera powered on later is
  invisible to the container even though the SDK still lists it (the ZWO SDK
  then reports `ASI_ERROR_CAMERA_REMOVED`).
- `--privileged` (or a `device_cgroup_rules` entry for character major 189)
  lets the container access the nodes.
- Device nodes keep the host's owner and mode, and hosts usually have no
  vendor udev rules, so the nodes are root-only. `pins-usb-permissions`
  (`docker/scripts/usb-permissions.sh`), run at start and as a supervised
  hotplug watcher, sets mode `0666` on the nodes of the vendors covered by the
  udev rules shipped in the image (`/usr/lib/udev/rules.d/99-*.rules`: ZWO,
  QHY, ToupTek, Player One, SVBony, Atik, ...). This changes the mode of the
  host's node, the same effect the vendor udev rule would have on the host.
  Alternatively install those rules on the host.
- Large-sensor USB3 cameras need a larger USB transfer buffer: the ZWO SDK
  cannot download frames bigger than
  `/sys/module/usbcore/parameters/usbfs_memory_mb` (kernel default 16 MB; a
  full RAW16 frame of a 16 MP camera is 32 MB), and the exposure then ends in
  "Camera Timeout - Camera did not set image as ready". The entrypoint raises
  the value to `PINS_USBFS_MEMORY_MB` (default 256, `0` leaves it alone) when
  the container is privileged, since the parameter is host-global and only
  writable with a read-write sysfs. Otherwise set it on the host
  (`usbcore.usbfs_memory_mb=256` on the kernel command line makes it
  permanent); the container log says so at start.
- Serial devices present at start can be passed with `--device /dev/ttyUSB0`
  (`pins` is in `dialout`); for serial hotplug bind-mount `/dev` instead.

INDI drivers and PHD2 run inside the container, so their USB devices are
covered by the same setup.

## Host shutdown and reboot

The "Shutdown" and "Restart" buttons in Touch-N-Stars run `sudo shutdown -h now`
and `sudo shutdown -r now` in the pins process. In the container they act on
the host machine, like on a Raspberry Pi installation: `/usr/sbin/shutdown`
(also `poweroff` and `reboot`) is a shim (`docker/power-shim.sh`) that asks
the host's logind over the host's system D-Bus socket to power off or reboot.
For that the socket must be mounted and the container must be privileged
(Docker's default AppArmor profile blocks D-Bus); `docker-compose.yml` does
both.

```bash
docker run -d --name pins --network host --stop-timeout 90 \
  -v "$PWD/data/home:/home/pins" -v "$PWD/data/images:/home/pins/Documents/N.I.N.A" \
  --privileged -v /dev/bus/usb:/dev/bus/usb \
  -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro \
  pins:local
```

Before the host goes down, the shim stops `pins` and `phd2` through
supervisord so that they write their settings (see "Where settings live"):
when the host shuts down, the Docker daemon gives containers only its own
shutdown timeout (15 s by default), which would cut the 60 s clean stop
short. The command returns at once and the stop runs detached, so the
button's request still gets its reply; progress is written to the container
log (`[pins-power] ...`). After a reboot Docker starts the container again
(`restart: unless-stopped`).

The `pins` user may run exactly `shutdown -h now` and `shutdown -r now` as
root (`docker/sudoers-pins`). Without the socket, or in an unprivileged
container, the buttons fail with an error in the pins log instead of doing
nothing (`host power control is not available: ...`). To check a setup
without stopping anything:

```bash
docker exec pins shutdown -h now --dry-run
```

Limitations: a Docker daemon with user namespace remapping maps the
container's root to an unprivileged host user, and logind (polkit) then
refuses the call; a host without systemd-logind cannot be controlled this
way; delayed shutdowns (`shutdown -h +5`) and cancelling are not supported.

## Extending the image

Use the image as a base and add what you need:

```dockerfile
FROM pins:local
RUN apt-get update && apt-get install -y --no-install-recommends <packages> && rm -rf /var/lib/apt/lists/*
```

Star databases and the sky map cache are handled by the helpers described
in "Downloading data".

## Verifying an image

`docker/scripts/smoke-test.sh [IMAGE]` starts a throwaway container with host
networking, waits for the core server, and checks `indiserver`, the plugin
folder, the ninaAPI version endpoint, the Touch-N-Stars page, the supervised
services, pinsdaemon's health endpoint, PHD2's port, ASTAP, the download
helpers and that the host power shim refuses cleanly without the D-Bus
socket. It prints the error lines of the application log and removes the
container afterwards.

## Multi-architecture

All from-source components (OpenCV, OpenCvSharp, INDI, NOVAS, SOFA) build for
the target platform, and the .NET publish uses `linux-arm64` when
`TARGETARCH=arm64`, so `docker buildx build --platform linux/arm64` produces a
Raspberry Pi image. Cross-building under QEMU emulation is very slow; building
natively on an arm64 host is recommended. The `linux-x64` image has been
verified; `linux-arm64` has not.

## How it relates to the existing build script

`build-and-install-pins-x64.sh` is an installer for a host machine: it
installs build prerequisites system-wide, builds OpenCV, libXISF, INDI, PHD2
and every plugin, packages them as `.deb` files and installs them with `dpkg`.
None of those steps fit in an image build, so the Dockerfile reuses its
individual pieces instead:

- the restore/build/publish commands and payload layout (`docker/scripts/build-core.sh`)
- the External bundle assembly (`docker/scripts/build-external.sh`)
- the plugin build flags and packaging rules (`docker/scripts/build-plugins.sh`)
- the INDI CMake configuration (`indi` stage) and the indi-3rdparty two-step build (`indi3p` stage)
- the PHD2 configure flags from its Debian packaging (`phd2` stage) and its service environment (`docker/pins-phd2.sh`)
- the pinsdaemon Debian package layout: venv, helper scripts in `/usr/local/bin`, `sysupdate-api` user and sudoers (`pinsdaemon` stage)
- the ASTAP and sky map cache setup steps from `BUILD_PINS.md` (`astap` stage, `pins-install-astap-db`, `pins-download-skymap`)

Runtime package lists for the from-source components are derived at build time
from their linked libraries (`docker/scripts/ldd-packages.sh`), and the final
image fails the build if any native dependency is unresolved
(`docker/scripts/check-native-deps.sh`).
