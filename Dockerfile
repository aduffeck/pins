# syntax=docker/dockerfile:1.7
#
# PI 'N' Stars (pins) container build.
#
# Produces a self-contained image of the pins astrophotography server:
#   * the .NET publish output of NINA/NINA.csproj (self-contained, RID-specific)
#   * the native External bundle (NOVAS, SOFA, JPLEPH, vendor camera/focuser SDKs)
#   * libOpenCvSharpExtern.so built from source against this Ubuntu release
#   * INDI server, core drivers and the indi-3rdparty vendor libraries/drivers
#   * PHD2 guiding (running on a virtual X display) and pinsdaemon
#   * the ASTAP plate solver (star databases and the offline sky map cache are
#     downloaded on demand into the data volume)
#   * optional plugin builds (ninaAPI + Touch-N-Stars by default)
#
# Usage and options: docker/README.md.  Typical build:
#   docker build --network=host -t pins .
#
ARG UBUNTU_VERSION=24.04
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0
ARG NODE_IMAGE=node:22-bookworm

############################################################################
# opencvsharp: static OpenCV (headless) + libOpenCvSharpExtern.so
#
# The OpenCvSharp NuGet runtime package is linked against Ubuntu 20.04/22.04
# libraries (libavcodec58, libtiff5, ...) and does not load on newer releases,
# so the native library is compiled here. Module selection mirrors
# OpenCvSharp's own Linux build; video/GUI backends are disabled so the result
# only depends on libc/libstdc++.
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS opencvsharp
ARG OPENCV_VERSION=4.11.0
ARG OPENCVSHARP_VERSION=4.11.0.20250507
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ca-certificates curl pkg-config \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl -fsSL --retry 3 "https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz" | tar xz \
 && curl -fsSL --retry 3 "https://github.com/opencv/opencv_contrib/archive/refs/tags/${OPENCV_VERSION}.tar.gz" | tar xz
RUN cmake -S "opencv-${OPENCV_VERSION}" -B opencv-build -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/opt/opencv \
      -D OPENCV_EXTRA_MODULES_PATH="/build/opencv_contrib-${OPENCV_VERSION}/modules" \
      -D BUILD_SHARED_LIBS=OFF \
      -D ENABLE_CXX11=ON \
      -D OPENCV_ENABLE_NONFREE=ON \
      -D BUILD_EXAMPLES=OFF -D BUILD_DOCS=OFF -D BUILD_PERF_TESTS=OFF -D BUILD_TESTS=OFF \
      -D BUILD_JAVA=OFF -D BUILD_opencv_apps=OFF -D BUILD_opencv_ts=OFF \
      -D BUILD_opencv_java_bindings_generator=OFF -D BUILD_opencv_python_bindings_generator=OFF \
      -D BUILD_opencv_python_tests=OFF -D BUILD_opencv_js=OFF -D BUILD_opencv_js_bindings_generator=OFF \
      -D BUILD_opencv_objc_bindings_generator=OFF \
      -D BUILD_opencv_barcode=OFF -D BUILD_opencv_bioinspired=OFF -D BUILD_opencv_ccalib=OFF \
      -D BUILD_opencv_datasets=OFF -D BUILD_opencv_dnn_objdetect=OFF -D BUILD_opencv_dpm=OFF \
      -D BUILD_opencv_fuzzy=OFF -D BUILD_opencv_gapi=ON -D BUILD_opencv_intensity_transform=OFF \
      -D BUILD_opencv_mcc=OFF -D BUILD_opencv_rapid=OFF -D BUILD_opencv_reg=OFF -D BUILD_opencv_stereo=OFF \
      -D BUILD_opencv_structured_light=OFF -D BUILD_opencv_surface_matching=OFF \
      -D BUILD_opencv_wechat_qrcode=ON -D BUILD_opencv_videostab=OFF \
      -D WITH_ADE=OFF -D WITH_GSTREAMER=OFF -D WITH_FFMPEG=OFF -D WITH_V4L=OFF -D WITH_1394=OFF \
      -D WITH_GTK=OFF -D WITH_QT=OFF -D WITH_OPENCL=OFF -D WITH_CUDA=OFF -D WITH_TBB=OFF \
      -D WITH_OPENEXR=ON -D BUILD_OPENEXR=ON -D BUILD_ZLIB=ON -D BUILD_PNG=ON -D BUILD_JPEG=ON \
      -D BUILD_TIFF=ON -D BUILD_WEBP=ON -D BUILD_OPENJPEG=ON -D BUILD_PROTOBUF=ON \
 && cmake --build opencv-build \
 && cmake --install opencv-build
COPY docker/scripts/common.sh docker/scripts/ldd-packages.sh /scripts/
RUN git clone --depth 1 --branch "${OPENCVSHARP_VERSION}" https://github.com/shimat/opencvsharp.git opencvsharp \
 && cmake -S opencvsharp/src -B ocs-build -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_PREFIX_PATH=/opt/opencv \
 && cmake --build ocs-build \
 && mkdir -p /out \
 && cp ocs-build/OpenCvSharpExtern/libOpenCvSharpExtern.so /out/ \
 && ldd /out/libOpenCvSharpExtern.so \
 && /scripts/ldd-packages.sh /out > /runtime-packages.txt \
 && cat /runtime-packages.txt

############################################################################
# indi: INDI server, client library and core drivers from source
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS indi
ARG INDI_VERSION=2.2.4.2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ca-certificates pkg-config zlib1g-dev \
      libcfitsio-dev libnova-dev libusb-1.0-0-dev libcurl4-gnutls-dev libgsl-dev \
      libjpeg-dev libfftw3-dev libtiff-dev libtheora-dev libev-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY docker/scripts/common.sh docker/scripts/ldd-packages.sh /scripts/
RUN git clone --depth 1 --branch "v${INDI_VERSION}" https://github.com/indilib/indi.git indi \
 && cmake -S indi -B indi-build -G Ninja \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr \
      -D UDEVRULES_INSTALL_DIR=/usr/lib/udev/rules.d \
      -D INDI_BUILD_SERVER=ON -D INDI_BUILD_CLIENT=ON -D INDI_BUILD_DRIVERS=ON -D INDI_BUILD_COMMON=ON \
      -D INDI_BUILD_QT_CLIENT=OFF -D INDI_BUILD_UNITTESTS=OFF -D INDI_BUILD_INTEGTESTS=OFF \
      -D INDI_BUILD_EXAMPLES=OFF -D INDI_BUILD_STATIC=OFF \
      -D CMAKE_DISABLE_FIND_PACKAGE_LibXISF=TRUE \
      -D FIX_WARNINGS=OFF \
 && cmake --build indi-build \
 && DESTDIR=/indi-root cmake --install indi-build \
 && rm -rf /indi-root/usr/include /indi-root/usr/lib/pkgconfig /indi-root/usr/lib/cmake \
           /indi-root/usr/lib/*/pkgconfig /indi-root/usr/lib/*/cmake \
 && find /indi-root/usr/lib -name '*.a' -delete \
 && test "$(ls /indi-root)" = "usr" \
 && /scripts/ldd-packages.sh /indi-root > /runtime-packages.txt \
 && cat /runtime-packages.txt
# INDI development files for the stages that build against it (PHD2, 3rd party).
RUN cmake --install indi-build >/dev/null && ldconfig

############################################################################
# indi3p: INDI 3rd-party vendor libraries (ASI, QHY, ToupTek, Player One,
# SVBony, ...) and drivers
############################################################################
FROM indi AS indi3p
ARG INDI_VERSION=2.2.4.1
# Drivers that cannot be built on this platform (missing packages in Ubuntu or
# Raspberry Pi specific hardware). Determined by configuring the full set.
ARG INDI_3RDPARTY_DISABLE="WITH_AHP_XC WITH_AHP_GT WITH_GPIO WITH_LIBCAMERA"
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libczmq-dev libftdi1-dev libavcodec-dev libavdevice-dev libavformat-dev libswscale-dev \
      libgps-dev libraw-dev libdc1394-dev libgphoto2-dev libboost-dev libboost-regex-dev \
      liblimesuite-dev libopencv-dev libzmq3-dev libudev-dev \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "v${INDI_VERSION}" https://github.com/indilib/indi-3rdparty.git indi-3rdparty \
 && cmake -S indi-3rdparty -B 3p-libs -G Ninja \
      -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr \
      -D UDEVRULES_INSTALL_DIR=/usr/lib/udev/rules.d \
      -D BUILD_LIBS=1 \
 && cmake --build 3p-libs \
 && DESTDIR=/indi3p-root cmake --install 3p-libs \
 && if [ -d /indi3p-root/lib ]; then mkdir -p /indi3p-root/usr/lib && cp -a /indi3p-root/lib/. /indi3p-root/usr/lib/ && rm -rf /indi3p-root/lib; fi \
 && cp -a /indi3p-root/. / && ldconfig
RUN set -eu; off=""; for o in ${INDI_3RDPARTY_DISABLE}; do off="$off -D$o=OFF"; done; \
    cmake -S indi-3rdparty -B 3p-drivers -G Ninja \
      -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr \
      -D UDEVRULES_INSTALL_DIR=/usr/lib/udev/rules.d \
      -D BUILD_LIBS=0 -D INDI_BUILD_UNITTESTS=OFF $off \
 && cmake --build 3p-drivers \
 && DESTDIR=/indi3p-root cmake --install 3p-drivers \
 && if [ -d /indi3p-root/lib ]; then mkdir -p /indi3p-root/usr/lib && cp -a /indi3p-root/lib/. /indi3p-root/usr/lib/ && rm -rf /indi3p-root/lib; fi \
 && rm -rf /indi3p-root/usr/include /indi3p-root/usr/lib/pkgconfig /indi3p-root/usr/lib/cmake \
           /indi3p-root/usr/lib/*/pkgconfig /indi3p-root/usr/lib/*/cmake \
 && find /indi3p-root/usr/lib -name '*.a' -delete \
 && for d in /indi3p-root/*; do case "$(basename "$d")" in usr|etc) ;; *) echo "unexpected top-level entry in indi3p root: $d" >&2; exit 1 ;; esac; done \
 && /scripts/ldd-packages.sh /indi3p-root > /runtime-packages.txt \
 && cat /runtime-packages.txt \
 && echo "3rd-party drivers: $(ls /indi3p-root/usr/bin | wc -l)"

############################################################################
# phd2: PHD2 guiding from the pins fork, against the INDI built above
#
# OPENSOURCE_ONLY=0 links the vendor camera SDKs PHD2 bundles (ZWO, QHY, ...).
# On x86_64 two of those static libraries define the same internal helper
# symbol; the linker is told to accept the duplicate, as the definitions are
# equivalent.
############################################################################
FROM indi AS phd2
ARG PHD2_REPO=https://github.com/acocalypso/phd2.git
ARG PHD2_BRANCH=master
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwxgtk3.2-dev libudev-dev libv4l-dev libeigen3-dev libgtest-dev libx11-dev \
      libopencv-dev gettext \
 && rm -rf /var/lib/apt/lists/*
RUN GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "${PHD2_BRANCH}" "${PHD2_REPO}" phd2 \
 && cmake -S phd2 -B phd2-build \
      -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr \
      -D USE_SYSTEM_LIBINDI=1 -D USE_SYSTEM_GTEST=1 -D USE_SYSTEM_LIBUSB=1 \
      -D OPENSOURCE_ONLY=0 -D FETCHCONTENT_FULLY_DISCONNECTED=OFF \
      -D CMAKE_EXE_LINKER_FLAGS=-Wl,--allow-multiple-definition \
 && cmake --build phd2-build --parallel \
 && DESTDIR=/phd2-root cmake --install phd2-build \
 && test "$(ls /phd2-root)" = "usr" \
 && /scripts/ldd-packages.sh /phd2-root > /runtime-packages.txt \
 && cat /runtime-packages.txt

############################################################################
# external: NINA/External native bundle (pins.external + NOVAS + SOFA)
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS external
ARG TARGETARCH
ARG PINS_EXTERNAL_REPO=https://github.com/nitr57/pins.external
ARG PINS_EXTERNAL_BRANCH=main
ARG JPLEPH_URL=https://github.com/isbeorn/nina.external/raw/refs/heads/master/JPLEPH
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential git git-lfs ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY NOVAS31 NOVAS31
COPY SOFA SOFA
COPY docker/scripts/common.sh docker/scripts/ldd-packages.sh docker/scripts/build-external.sh /scripts/
RUN /scripts/build-external.sh /out/External \
 && /scripts/ldd-packages.sh /out/External > /runtime-packages.txt \
 && cat /runtime-packages.txt

############################################################################
# pinsdaemon: system management API (Python) with its virtual environment
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS pinsdaemon
ARG PINSDAEMON_REPO=https://github.com/Touch-N-Stars/pinsdaemon
ARG PINSDAEMON_BRANCH=""
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    set -eu; \
    git clone --depth 1 ${PINSDAEMON_BRANCH:+--branch "$PINSDAEMON_BRANCH"} "${PINSDAEMON_REPO}" /opt/pinsdaemon; \
    cd /opt/pinsdaemon; rm -rf .git tests docs; \
    python3 -m venv venv; \
    venv/bin/pip install -r requirements.txt; \
    mkdir -p logs

############################################################################
# astap: ASTAP command-line plate solver
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS astap
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
COPY docker/scripts/common.sh docker/scripts/fetch-astap.sh /scripts/
RUN /scripts/fetch-astap.sh /astap

############################################################################
# frontend: Touch-N-Stars web app (only when the touch-n-stars plugin is built)
############################################################################
FROM ${NODE_IMAGE} AS frontend
ARG BUILD_PLUGINS="ninaapi touch-n-stars polaralignment joko livestack nightsummary"
ARG TNS_FRONTEND_REPO=https://github.com/Touch-N-Stars/Touch-N-Stars.git
ARG TNS_FRONTEND_BRANCH=develop
WORKDIR /frontend
# npm git dependencies of the web app use SSH GitHub URLs; there are no SSH
# credentials in the build, so let git fetch them anonymously over HTTPS.
RUN git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/" \
 && git config --global --add url."https://github.com/".insteadOf "git@github.com:"
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    set -eu; mkdir -p /frontend/dist; \
    case " ${BUILD_PLUGINS} " in \
      *" touch-n-stars "*) \
        git clone --depth 1 --branch "${TNS_FRONTEND_BRANCH}" "${TNS_FRONTEND_REPO}" src; \
        cd src; npm install; npm run build; \
        cp -a dist/. /frontend/dist/ ;; \
      *) echo "Touch-N-Stars plugin not selected; skipping web app build" ;; \
    esac

############################################################################
# build: .NET publish of the core application
############################################################################
FROM ${DOTNET_SDK_IMAGE} AS build
ARG TARGETARCH
ARG BUILD_CONFIGURATION=Release
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    BUILD_CONFIGURATION=${BUILD_CONFIGURATION}
WORKDIR /src
COPY . .
COPY --from=external /out/External NINA/External
COPY --from=opencvsharp /out/libOpenCvSharpExtern.so /opt/opencvsharp/libOpenCvSharpExtern.so
RUN --mount=type=cache,target=/root/.nuget/packages,sharing=locked \
    docker/scripts/build-core.sh /out/pins

############################################################################
# plugins: optional plugin builds against the core above
############################################################################
FROM build AS plugins
ARG BUILD_PLUGINS="ninaapi touch-n-stars polaralignment joko livestack nightsummary"
COPY --from=frontend /frontend/dist /frontend-dist
RUN --mount=type=cache,target=/root/.nuget/packages,sharing=locked \
    docker/scripts/build-plugins.sh /out/pins /out/plugins "${BUILD_PLUGINS}"

############################################################################
# runtime
############################################################################
FROM ubuntu:${UBUNTU_VERSION} AS runtime
ARG PINS_UID=1000
ARG PINS_GID=1000
ARG PINSDAEMON_UID=990
ARG EXTRA_PACKAGES=""
ENV DEBIAN_FRONTEND=noninteractive

COPY docker/scripts/common.sh docker/scripts/check-native-deps.sh docker/scripts/indi-3rdparty-registry.py /usr/local/lib/pins/
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/pins-entrypoint
COPY --chmod=755 docker/pins-phd2.sh /usr/local/bin/pins-phd2
COPY --chmod=755 docker/scripts/usb-permissions.sh /usr/local/bin/pins-usb-permissions
COPY --chmod=755 docker/scripts/install-astap-db.sh /usr/local/bin/pins-install-astap-db
COPY --chmod=755 docker/scripts/fetch-skymap.sh /usr/local/bin/pins-download-skymap
COPY --chmod=755 docker/systemctl-shim.sh /usr/local/lib/pins/systemctl-shim
COPY --chmod=440 docker/sudoers-pinsdaemon /etc/sudoers.d/pinsdaemon
COPY --chmod=755 docker/power-shim.sh /usr/local/lib/pins/power-shim
COPY --chmod=440 docker/sudoers-pins /etc/sudoers.d/pins
COPY docker/supervisord.conf /etc/pins/supervisord.conf
COPY --from=indi /indi-root/ /
COPY --from=indi3p /indi3p-root/ /
COPY --from=phd2 /phd2-root/ /
COPY --from=indi /runtime-packages.txt /tmp/pins-deps/indi.txt
COPY --from=indi3p /runtime-packages.txt /tmp/pins-deps/indi3p.txt
COPY --from=phd2 /runtime-packages.txt /tmp/pins-deps/phd2.txt
COPY --from=opencvsharp /runtime-packages.txt /tmp/pins-deps/opencvsharp.txt
COPY --from=external /runtime-packages.txt /tmp/pins-deps/external.txt

# Runtime packages: .NET self-contained prerequisites (ICU, OpenSSL, Kerberos),
# tools the application shells out to (pkill from procps, mkfifo, curl for the
# health check), USB access for the vendor SDKs, libgphoto2 for DSLR cameras
# (the SDK wrapper loads the unversioned library names, which only the -dev
# packages provide, hence the symlinks), hidapi for the Oasis SDK (loaded the
# same way; without it the Oasis library aborts the process on first use),
# cfitsio (FITS reading and writing) and LibRaw (DSLR raw conversion), which
# pins dlopens by their unversioned names as well, the
# process supervisor, inotify-tools for the USB permission helper, unzip for
# the sky map download helper, a virtual X
# server and fonts for PHD2, Python and sudo for pinsdaemon, and everything
# the from-source components were linked against (lists generated in their
# build stages). Package names that carry a version or t64 suffix are looked
# up so the same Dockerfile works across Ubuntu releases.
# There is no systemd in the container: systemctl becomes a shim onto
# supervisord (PHD2 control by pinsdaemon) and shutdown/poweroff/reboot
# become the host power control shim (docker/power-shim.sh, used by the
# Touch-N-Stars Shutdown/Restart buttons); the originals are diverted.
RUN set -eu; \
    apt-get update; \
    pick() { apt-cache search --names-only "$1" | awk '{print $1}' | sort -V | tail -n1; }; \
    apt-get install -y --no-install-recommends \
      ca-certificates tzdata curl procps libusb-1.0-0 libudev1 libgssapi-krb5-2 \
      supervisor xvfb fonts-dejavu-core python3 sudo libhidapi-hidraw0 libhidapi-libusb0 inotify-tools unzip \
      "$(pick '^libicu[0-9]+$')" "$(pick '^libssl3(t64)?$')" \
      "$(pick '^libgphoto2-6(t64)?$')" "$(pick '^libgphoto2-port12(t64)?$')" \
      "$(pick '^libcfitsio[0-9]+(t64)?$')" "$(pick '^libraw[0-9]+(t64)?$')" \
      $(cat /tmp/pins-deps/*.txt | sort -u | tr '\n' ' ') ${EXTRA_PACKAGES}; \
    rm -rf /var/lib/apt/lists/* /tmp/pins-deps; \
    unversioned="libgphoto2 libgphoto2_port libhidapi-hidraw libhidapi-libusb libcfitsio libraw"; \
    for lib in $unversioned; do \
      p="$(ls /usr/lib/*/"$lib".so.[0-9]* 2>/dev/null | sort -V | head -n1)"; \
      [ -n "$p" ] || { echo "runtime library $lib is not installed" >&2; exit 1; }; \
      ln -sfn "$(basename "$p")" "$(dirname "$p")/$lib.so"; \
    done; \
    ldconfig; \
    for lib in $unversioned; do \
      python3 -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$lib.so" \
        || { echo "cannot dlopen $lib.so" >&2; exit 1; }; \
    done; \
    if getent passwd "${PINS_UID}" >/dev/null; then userdel -r "$(getent passwd "${PINS_UID}" | cut -d: -f1)"; fi; \
    if getent group "${PINS_GID}" >/dev/null; then groupdel "$(getent group "${PINS_GID}" | cut -d: -f1)"; fi; \
    groupadd -g "${PINS_GID}" pins; \
    useradd -m -u "${PINS_UID}" -g pins -s /bin/bash pins; \
    for g in dialout plugdev video; do getent group "$g" >/dev/null && usermod -aG "$g" pins; done; \
    groupadd -r -g "${PINSDAEMON_UID}" sysupdate-api; \
    useradd -r -u "${PINSDAEMON_UID}" -g sysupdate-api -d /opt/pinsdaemon -s /usr/sbin/nologin sysupdate-api; \
    groupadd -r pinsctl; usermod -aG pinsctl pins; usermod -aG pinsctl sysupdate-api; \
    mkdir -p /home/pins/.local/share/NINA /home/pins/.config /home/pins/Documents/N.I.N.A /home/pins/Documents/INDI; \
    chown -R pins:pins /home/pins; \
    cp /etc/pins/supervisord.conf /etc/supervisor/supervisord.conf; \
    if [ -e /usr/bin/systemctl ]; then dpkg-divert --local --rename --add /usr/bin/systemctl; fi; \
    install -m 755 /usr/local/lib/pins/systemctl-shim /usr/bin/systemctl; \
    for c in shutdown poweroff reboot; do \
      if [ -e "/usr/sbin/$c" ] || [ -L "/usr/sbin/$c" ]; then dpkg-divert --local --rename --add "/usr/sbin/$c"; fi; \
      install -m 755 /usr/local/lib/pins/power-shim "/usr/sbin/$c"; \
    done

# pinsdaemon: application + venv, and its helper scripts where the Debian
# package installs them. Only the systemctl shim (PHD2 control) and the ASTAP
# helpers are usable inside a container; see docker/README.md.
COPY --from=pinsdaemon --chown=${PINSDAEMON_UID}:${PINSDAEMON_UID} /opt/pinsdaemon /opt/pinsdaemon
RUN set -eu; \
    for f in /opt/pinsdaemon/scripts/*; do \
      case "$f" in *.sh|*.py|*/pins-rig-name) install -m 755 "$f" /usr/local/bin/ ;; esac; \
    done

# ASTAP: CLI at the location pins expects by default. Star databases are not
# bundled; /opt/astap (where ASTAP's database packages install) and
# /usr/share/astap/data (where the CLI looks) both point into the data volume,
# so `pins-install-astap-db` and pinsdaemon's installer persist their result.
RUN --mount=type=bind,from=astap,source=/astap,target=/mnt/astap \
    set -eu; \
    install -m 755 /mnt/astap/bin/astap_cli /usr/local/bin/astap_cli; \
    ln -sfn /usr/local/bin/astap_cli /usr/bin/astap; \
    mkdir -p /home/pins/.local/share/astap /usr/share/astap; \
    chown pins:pins /home/pins/.local/share/astap; \
    ln -sfn /home/pins/.local/share/astap /opt/astap; \
    ln -sfn /home/pins/.local/share/astap /usr/share/astap/data

# Touch-N-Stars lists INDI drivers from its embedded defaults plus the
# registry ~/Documents/INDI/3rdparty.json, which pinsdaemon fills when driver
# packages are installed on a Pi. Generate it for the drivers built into the
# image; the entrypoint merges it into the user's registry at start.
RUN mkdir -p /opt/pins-data \
 && python3 /usr/local/lib/pins/indi-3rdparty-registry.py generate /opt/pins-data/indi-3rdparty.json

# Application payload and bundled plugins, owned by the runtime user (chown at
# copy time; a later recursive chown would duplicate every file in a new layer).
COPY --from=build --chown=${PINS_UID}:${PINS_GID} /out/pins /opt/pins
COPY --from=plugins --chown=${PINS_UID}:${PINS_GID} /out/plugins /opt/pins-plugins

RUN /usr/local/lib/pins/check-native-deps.sh /opt/pins /usr/bin /usr/lib/*/libindi* /usr/lib/*/indi /usr/lib/*.so* /usr/lib/phd2

ENV HOME=/home/pins \
    PINS_APP_DIR=/opt/pins \
    PINS_PLUGIN_API_VERSION=3.0.0 \
    PHD2_AUTOSTART=true \
    PINS_DISPLAY=:99 \
    PINSDAEMON_AUTOSTART=true \
    PINSDAEMON_API_TOKEN=zZDqJ3IKeFaIZqG2JIFvsxzA5E48GC2gyGVagHFZqC0OMtgoupUDZCPhQDYKm35d \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /opt/pins

# Application data (profiles, logs, plugins, PHD2 config, images) lives in the
# home directory; mount it as a volume to persist it.
VOLUME ["/home/pins"]

# 4782 core SignalR hubs, 1888 ninaAPI, 5000 Touch-N-Stars web UI,
# 7624 indiserver, 4400 PHD2 server API, 8000 pinsdaemon
EXPOSE 4782 1888 5000 7624 4400 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -s -o /dev/null http://127.0.0.1:4782/ || exit 1

ENTRYPOINT ["/usr/local/bin/pins-entrypoint"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
