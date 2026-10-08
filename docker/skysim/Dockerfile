# Sky Simulator sidecar: Sky Simulator (Han Kleijn, https://sky-simulator.sourceforge.io)
# on its own virtual X display, as a simulated rig for pins. It shares the pins
# container's network namespace; the indi_skysimulator drivers in the pins
# image relay its INDI devices into pins' indiserver. See README.md.
#
#   docker compose --profile skysim build skysim
#   docker build --network host -t skysim:local docker/skysim
FROM ubuntu:24.04

# Sky Simulator 4.0.0rc1 (2026-08-08), the Linux amd64 GTK3 build
ARG SKYSIM_URL=https://sourceforge.net/projects/sky-simulator/files/program/linux_installer/sky_simulator_amd64_gtk3.tar.gz/download
ARG SKYSIM_SHA256=68cb62243e723e4515dbed9809e2b9dde4df001e37714dd761d958020f57d663
# UID/GID of the in-container user; match the owner of the bind-mounted home.
ARG SKYSIM_UID=1000
ARG SKYSIM_GID=1000
ENV DEBIAN_FRONTEND=noninteractive

# xdotool presses "Start simulation", x11vnc is the optional view of the GUI.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xvfb xdotool x11vnc libgtk-3-0t64 libharfbuzz-gobject0 fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/skysim.tgz "$SKYSIM_URL" \
 && echo "$SKYSIM_SHA256  /tmp/skysim.tgz" | sha256sum -c - \
 && tar xzf /tmp/skysim.tgz -C / opt/sky_simulator \
 && rm /tmp/skysim.tgz \
 && ldd /opt/sky_simulator/sky_simulator | (! grep 'not found')

RUN set -eu; \
    if getent passwd "${SKYSIM_UID}" >/dev/null; then userdel -r "$(getent passwd "${SKYSIM_UID}" | cut -d: -f1)"; fi; \
    if getent group "${SKYSIM_GID}" >/dev/null; then groupdel "$(getent group "${SKYSIM_GID}" | cut -d: -f1)"; fi; \
    groupadd -g "${SKYSIM_GID}" sim; \
    useradd -m -u "${SKYSIM_UID}" -g sim -s /bin/bash sim

COPY sky_simulator.cfg /opt/sky_simulator/default.cfg
COPY --chmod=755 skysim-entrypoint.sh /usr/local/bin/skysim-entrypoint
COPY --chmod=755 skysim-run.sh /usr/local/bin/skysim-run

# SKYSIM_DISPLAY: with host networking the X socket name is shared with the
# host and the pins container (:99), so use a display number of its own.
ENV HOME=/home/sim \
    SKYSIM_DISPLAY=:77 \
    SKYSIM_VNC=false \
    SKYSIM_VNC_PORT=5900

# Settings (~/.config/sky_simulator) and Sky Simulator's Documents folder.
VOLUME ["/home/sim"]

ENTRYPOINT ["/usr/local/bin/skysim-entrypoint"]
CMD ["/usr/local/bin/skysim-run"]
