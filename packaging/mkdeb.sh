#!/bin/sh
#
# packaging/mkdeb.sh - a .deb of this checkout, for CI and testing
#
#   sh packaging/mkdeb.sh [OUTDIR]
#
# Not Debian's tiger and not a candidate for it (that packaging is for
# later): a CI-built tigris, co-installable beside tiger. Builds from a
# copy of the checkout, so the tree stays clean, and writes
# tigris_<version>-1_<arch>.deb into OUTDIR (default: the checkout).
# Needs dpkg-dev tools, a C compiler and make.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
OUT=${1:-$TIGER}

for t in dpkg-deb dpkg; do
  command -v $t >/dev/null 2>&1 || { echo "mkdeb.sh: $t is needed"; exit 1; }
done
command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || { echo "mkdeb.sh: a C compiler is needed"; exit 1; }
command -v make >/dev/null 2>&1 || { echo "mkdeb.sh: make is needed"; exit 1; }
[ -d "$OUT" ] || { echo "mkdeb.sh: $OUT is not a directory"; exit 1; }

VERSION=`cat "$TIGER/version"`
ARCH=`dpkg --print-architecture`
W=`mktemp -d`
trap 'rm -rf "$W"' 0

( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( mkdir "$W/src" && cd "$W/src" && tar -xf - )
cd "$W/src" || exit 1
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
  --with-tigerhome=/usr/lib/tigris --with-tigerconfig=/etc/tigris \
  --with-tigerwork=/var/lib/tigris --with-tigerlog=/var/log/tigris \
  --with-tigerbin=/usr/sbin >"$W/configure.log" 2>&1 || { tail -5 "$W/configure.log"; exit 1; }
make >"$W/make.log" 2>&1 || { tail -5 "$W/make.log"; exit 1; }
make install DESTDIR="$W/stage" >"$W/install.log" 2>&1 || { tail -5 "$W/install.log"; exit 1; }
sh "$TIGER/packaging/stage.sh" "$W/stage" /usr/lib/tigris || exit 1

mkdir "$W/stage/DEBIAN"
cat > "$W/stage/DEBIAN/control" <<EOF
Package: tigris
Version: $VERSION-1
Section: admin
Priority: optional
Architecture: $ARCH
Depends: libc6
Maintainer: Andrei Trimbitas <a.trimbitas@oldforge.tech>
Homepage: https://github.com/creativeheadz/tigris
Description: Security auditor for Linux, descended from TIGER
 Tigris audits a Linux system against 63 checks and explains every
 finding, with JSON output, offline auditing of images that are not
 running, and per-finding compliance controls. It installs beside
 Debian's tiger under its own name and paths.
EOF
printf '/etc/tigris/tigris.conf\n/etc/tigris/cronrc\n' > "$W/stage/DEBIAN/conffiles"

DEB="$OUT/tigris_${VERSION}-1_${ARCH}.deb"
dpkg-deb --root-owner-group -b "$W/stage" "$DEB" || exit 1
echo "$DEB"
