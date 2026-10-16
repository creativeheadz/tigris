#!/bin/sh
#
# packaging/stage.sh - reshape a DESTDIR install into the distro package layout
#
#   sh packaging/stage.sh DESTDIR [LIBDIR] [SBINDIR]
#
# DESTDIR holds a `make install DESTDIR=...` tree configured --prefix=/usr
# with the tigris paths (--with-tigerhome=$LIBDIR, --with-tigerconfig=
# /etc/tigris, --with-tigerwork=/var/lib/tigris, --with-tigerlog=
# /var/log/tigris, --with-tigerbin=$SBINDIR). LIBDIR defaults to
# /usr/lib/tigris (/usr/lib64/tigris on 64-bit rpm distributions);
# SBINDIR defaults to /usr/sbin (/usr/bin where sbin merged into bin).
#
# The package installs beside the distribution's tiger, not over it:
# only the tigris entry points stay in sbin, and only tigris paths are
# named. Every rewrite asserts the text it replaces, so a source change
# that moves it fails the build instead of shipping a broken package.
#
D=${1:?usage: stage.sh DESTDIR [LIBDIR] [SBINDIR]}
LIB=${2:-/usr/lib/tigris}
SBIN=${3:-/usr/sbin}
case "$LIB" in /*) ;; *) echo "stage.sh: LIBDIR must be absolute"; exit 1;; esac
case "$SBIN" in /*) ;; *) echo "stage.sh: SBINDIR must be absolute"; exit 1;; esac
R=${LIB#/}
S=${SBIN#/}

fail=0
need() {
  [ -e "$D/$1" ] || { echo "stage.sh: $D/$1 is missing ($2)"; fail=1; }
}
need $S/tiger "sbin binary"
need $S/tigris "sbin binary"
need $S/tigris-diff "sbin binary"
need $S/tigris-accept "sbin binary"
need $S/tigris-explain "sbin binary"
need $S/tigercron "sbin binary"
need "$R/tigris-explain" "helper beside the install (HELPERS in Makefile.in)"
need "$R/tigris-diff" "helper beside the install (HELPERS in Makefile.in)"
need etc/tigris/tigris.conf "config file"
need etc/tigris/cronrc "config file"
need usr/share/man/man8/tigris.8 "man page"
[ "$fail" -ne 0 ] && exit 1

# sbin keeps the tigris entry points; the rest run from the library dir
mv "$D/$S/tiger" "$D/$S/tigris-explain" "$D/$S/tigercron" "$D/$R/"

# `tigris explain` looks beside itself for tigris-explain; bake the library dir
# the way make install bakes the other paths
T=$D/$S/tigris
grep -q '`dirname "$0"`/tigris-explain' "$T" || { echo "stage.sh: the explain line moved in tigris"; exit 1; }
sed -i 's#`dirname "$0"`/tigris-explain#'"$LIB"'/tigris-explain#' "$T"

# the log and accepted-file defaults name the tigris directories
F=$D/$S/tigris-diff
grep -q '/var/log/tiger' "$F" || { echo "stage.sh: the log default moved in tigris-diff"; exit 1; }
sed -i 's#/var/log/tiger#/var/log/tigris#' "$F"
A=$D/$S/tigris-accept
grep -q '/etc/tigris/tigris.accepted' "$A" || { echo "stage.sh: the accepted-file default moved in tigris-accept"; exit 1; }

# man pages: the tigris ones only
rm -f "$D/usr/share/man/man8/tiger.8" "$D/usr/share/man/man8/tigris-explain.8" "$D/usr/share/man/man8/tigercron.8"

# build droppings stay out of the package
rm -f "$D/$R/doc/Makefile" "$D/$R/doc/Makefile.in"

# check_network is perl and undispatched (commented out in tiger); it
# stays out so the package keeps its no-dependencies promise
if grep -q '^[^#]*run_script check_network' "$D/$S/tigris"; then
  echo "stage.sh: check_network is dispatched now; revisit the package file list"
  exit 1
fi
[ -f "$D/$R/scripts/check_network" ] || { echo "stage.sh: scripts/check_network moved"; exit 1; }
rm -f "$D/$R/scripts/check_network"

echo "staged under $D"
