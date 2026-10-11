# Tigris in a container: audit what is not running (a container image's
# root filesystem, a mounted disk, a VM snapshot, this host's own disk)
# with tigris --root, and every distribution's package tools to do it
# with: dpkg and apt, rpm, dnf and zypper, pacman, and apk.
#
#   docker build -t tigris .
#   docker run --rm -v /path/to/rootfs:/target:ro -v "$PWD/reports:/opt/tigris/log" \
#     tigris --root /target
#
# Nothing under /target is run: its files are read, and these tools are
# pointed at its package databases. Mount it read-only (dnf 4 and zypper
# then cannot count updates; everything else reads as before).

# apk for Alpine roots: Debian has no apk-tools, so the static one Alpine
# ships is copied in
FROM alpine:3@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS apk
RUN apk add --no-cache apk-tools-static

# (pinned by digest, so that a rebuild is the same image; move the
# digests when a release is cut: docker buildx imagetools inspect)
FROM debian:stable-slim@sha256:eb593cf2c358cacef45ca0a424bbc7d30cfa3466265fc2662b9466a0ca6ba1c5
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      binutils file procps diffutils bsdextrautils \
      sudo systemd \
      rpm dnf zypper pacman-package-manager \
 && rm -rf /var/lib/apt/lists/*
COPY --from=apk /sbin/apk.static /usr/local/sbin/apk
COPY . /opt/tigris
# Tigris runs only check scripts owned by the user running it: root here
RUN chown -R root:root /opt/tigris \
 && chmod -R go-w /opt/tigris \
 && mkdir -p /opt/tigris/log /opt/tigris/run
WORKDIR /opt/tigris
LABEL org.opencontainers.image.title="Tigris" \
      org.opencontainers.image.description="A security auditor for Linux, in POSIX shell; tigris --root audits a system that is not running" \
      org.opencontainers.image.source="https://github.com/creativeheadz/tigris" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"
ENTRYPOINT ["/opt/tigris/tigris"]
CMD ["-h"]
