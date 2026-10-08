# Sky Simulator sidecar

[Sky Simulator](https://sky-simulator.sourceforge.io) by Han Kleijn (author of
ASTAP/HNSKY) simulates a mount, an imaging camera, a guide camera, a focuser, a
filter wheel and a rotator. It renders star fields from its own star database
for wherever the mount points, including focus blur, tracking and periodic
error, seeing noise, polar misalignment and backlash. That makes it a test rig
for pins and the native guider. Version 4.0.0rc1 (2026-08-07) has a Linux build
with a built-in INDI server, which this sidecar uses.

```
 network namespace of the pins service (127.0.0.1 is shared)
 ┌───────────────────────────────────────┐   ┌──────────────────────────────────┐
 │ pins container                        │   │ skysim container (this folder)   │
 │  pins ── indiserver :7624             │   │  Xvfb :77 ── sky_simulator (GTK) │
 │            ├ indi_skysimulator ───────┼──►│  INDI server 127.0.0.1:7625      │
 │            ├ indi_skysimulator_ccd ───┼──►│  Alpaca      127.0.0.1:11111     │
 │            └ indi_skysimulator_guide ─┼──►│  x11vnc :5900 (optional)         │
 └───────────────────────────────────────┘   └──────────────────────────────────┘
```

## Start

```bash
docker compose --profile skysim build skysim     # once, a few seconds (also builds on first `up`)
docker compose --profile skysim up -d            # pins + skysim
docker compose --profile skysim logs skysim      # "skysim: simulation running, INDI server on 127.0.0.1:7625"
```

Without `--profile skysim`, compose ignores the service. pins runs as before,
and the relay drivers in the image do nothing.

The pins image must contain the relay drivers. Every image built from this
branch's `Dockerfile` does. The sidecar is amd64 only, because Sky Simulator
has no arm64 Linux build.

## Select the devices

In Touch-N-Stars, pick the INDI drivers like you would for real hardware:

| pins device | INDI driver | Device |
| --- | --- | --- |
| Mount | Sky Simulator Mount (`indi_skysimulator`) | Sky Simulator Mount |
| Camera | Sky Simulator Camera (`indi_skysimulator_ccd`) | Sky Simulator Camera |
| Focuser | Sky Simulator Focuser (`indi_skysimulator`) | Sky Simulator Focuser |
| Filter wheel | Sky Simulator Filter Wheel (`indi_skysimulator`) | Sky Simulator Filter Wheel |
| Rotator | Sky Simulator Rotator (`indi_skysimulator`) | Sky Simulator Rotator |
| Native guider camera | Sky Simulator Guide Camera (`indi_skysimulator_guide`) | Sky Simulator Guide Camera |

For the native guider:

- Set **focal length 330 mm**, matching the simulator's camera tab.
- Leave the pulse output on the mount. The Sky Simulator mount supports
  `TELESCOPE_TIMED_GUIDE_NS/WE`.

For PHD2, select the same INDI devices on its default server localhost:7624.
This is not tested yet.

Things to expect:

- **Location prompt.** On the first mount connect, Touch-N-Stars asks whether
  to sync the site location, because the simulator's (53°N 6.5°E) differs
  from the profile's. Choose "to telescope", or set the profile's mount option
  "location sync" to *to telescope*. Scripts must set
  `TelescopeSettings-TelescopeLocationSyncDirection=TOTELESCOPE`; otherwise
  the connect call waits for the unanswered prompt.
- **Slow mount connect.** Connecting the mount takes about 20 s. pins waits
  for `TELESCOPE_TRACK_MODE`, which the Sky Simulator mount doesn't define (it
  has `TELESCOPE_TRACK_STATE`), then logs a warning and carries on.
- **Same image on both cameras.** Sky Simulator renders one sky with one
  geometry, so the main and guide cameras show the same image.
- **Alpaca duplicates.** Sky Simulator's Alpaca server runs alongside INDI,
  so pins' device lists may also show "Alpaca" entries for it. Use the INDI
  ones.

## Settings

Settings live in `data/skysim/.config/sky_simulator/sky_simulator.cfg`. On
first start the file is seeded from `sky_simulator.cfg` in this folder.

To change them in the GUI:

1. Set `SKYSIM_VNC: "true"` in the compose file and recreate the container.
2. Connect a VNC viewer to port 5900 of the pins host (or of the pins
   container's bridge IP).
3. Change the settings and press "Save settings".

Alternatively, edit the file and run `docker compose --profile skysim restart skysim`.

| Tab | Setting (cfg key) | Default |
| --- | --- | --- |
| Camera | width/height, pixel size, focal length (`width_pixels`, `height_pixels`, `px_size`, `focal_length`) | 1280×960, 5 µm, 330 mm = 3.12″/px. That is the scale of an ASI120MM-S (3.75 µm) on a 248 mm guide scope. **4.0.0rc1 always reports 5.00 µm in INDI `CCD_INFO`**, whatever the pixel size setting, so keep 5 µm and choose the focal length for the scale you want. |
| Camera | Fast simulation (`fastsim`) | off. On, exposures return immediately instead of after their duration. |
| Mount | Error α/δ: square wave, sinusoid (periodic error) with period and amplitude, random noise (`ra_*`/`dec_*_error_*`, `*_random_noise_sigma`) | RA sinusoid 0.2 s amplitude over 400 s, 0.5″ noise in RA and Dec. RA amplitudes are in seconds of RA. |
| Mount | Polar alignment error, mount backlash (`polar_alignment`, `elevation_e`, `azimuth_e`, `backlash_mount`) | off |
| Mount | Site (`latitude`, `longitude`) | 53 / 6.5; replaced by the profile's site with "location sync to telescope" |
| Image source | "No star (Cover telescope)" for darks, hot pixels (`hot_pixels`) | stars, 0 hot pixels |
| Indi | Port (`indi_port`) | 7625. If you change it, set `SKYSIM_INDI_PORT` for the pins service too. |

Environment of the skysim service:

| Variable | Default | Effect |
| --- | --- | --- |
| `SKYSIM_VNC` | `false` | VNC view of the simulator GUI. Without `SKYSIM_VNC_PASSWORD`, any client can connect, which matters under host networking. |
| `SKYSIM_VNC_PORT` | `5900` | VNC port |
| `SKYSIM_VNC_PASSWORD` | unset | VNC password |
| `SKYSIM_DISPLAY` | `:77` | Virtual X display. Under host networking the X socket name is shared with the host and the pins container (`:99`). |

The relay drivers in the pins container read `SKYSIM_HOST` (default
`127.0.0.1`) and `SKYSIM_INDI_PORT` (default `7625`).

## Networking

Sky Simulator's INDI and Alpaca servers listen on 127.0.0.1 only, so the
sidecar joins the pins service's network namespace
(`network_mode: "service:pins"`). With pins on host networking, that is the
host's namespace, and the simulator's ports 7625 and 11111 (127.0.0.1) and
UDP 32227 (Alpaca discovery) are taken there.

With pins on bridge networking, the namespace belongs to the pins container.
If that container is stopped or restarted alone, restart the sidecar as well
(`docker compose --profile skysim restart skysim`). Otherwise it keeps the old
namespace and the relay drivers can't reach it.

## Why relay drivers

pins only connects to its own indiserver on localhost:7624
(`NINA.INDI/INDIClient.cs`), and the native guider only accepts INDI cameras
whose `DRIVER_EXEC` equals its configured driver
(`pins-guider` `IndiGuideCamera.cs`). indiserver can chain remote devices
(`start Sky Simulator Camera@127.0.0.1:7625` through pins' FIFO). Plain
chaining falls short in three ways:

- **Duplicate commands.** Sky Simulator ignores the device in `getProperties`
  and sends all six devices over every link. With one chained link per pins
  device type, indiserver forwards each command once per link. In testing, one
  guide pulse reached the simulator three times.
- **15 s timeout.** pins waits for a `DRIVER_INFO` whose `DRIVER_EXEC` equals
  the driver name, which never happens for an `@` name.
- **No guide camera.** The native guider rejects the guide camera, because its
  `DRIVER_EXEC` (`indi_skysimulator_guide`) doesn't match the `@` name.

`indi_skysimulator` and its `_ccd`/`_guide` names are local drivers named like
Sky Simulator's `DRIVER_EXEC` values. indiserver starts them like any driver.
Each one opens its own connection to the simulator and relays only its own
devices, so every command reaches the simulator exactly once and pins matches
the drivers immediately. `skysimulator.xml` lists them for Touch-N-Stars
(through the image's INDI driver registry) and for the native guider's camera
list.

## Files

| File | Used by | Purpose |
| --- | --- | --- |
| `Dockerfile` | sidecar | Ubuntu 24.04, Xvfb, GTK3, xdotool, x11vnc and the Sky Simulator tarball (pinned sha256) |
| `skysim-entrypoint.sh` | sidecar | Prepares the X socket directory and the home volume, drops to user `sim` |
| `skysim-run.sh` | sidecar | Xvfb, optional VNC, seeds the settings, starts Sky Simulator and presses "Start simulation" (xdotool) |
| `sky_simulator.cfg` | sidecar | Default settings (all devices on INDI) |
| `indi_skysimulator` | pins image | Relay driver (Python, no dependencies), installed with `_ccd`/`_guide` symlinks |
| `skysimulator.xml` | pins image | INDI driver definitions in `/usr/share/indi` |

## Caveats

- **Release candidate.** Sky Simulator 4.0.0rc1 is a release candidate. A newer
  tarball means updating `SKYSIM_SHA256`.
- **Button click.** "Start simulation" is pressed by clicking at a fixed
  position in the window, after resetting the window's position and size. If a
  future version moves the button, the log says the INDI server didn't come up.
- **rc1 bugs worth reporting** on the
  [forum](https://sourceforge.net/p/sky-simulator/discussion/):
  - INDI `CCD_INFO` always says 5 µm.
  - Saving settings fails when `~/.config/sky_simulator/` doesn't exist (the
    sidecar creates it).
  - The INDI server ignores the device in `getProperties`.
