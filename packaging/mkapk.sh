#!/bin/sh
#
# packaging/mkapk.sh - an .apk of this checkout, for CI and testing
#
#   sh packaging/mkapk.sh [OUTDIR]
#
# Runs as a non-root user on Alpine (abuild refuses root): CI creates
# the builder first, in the abuild group with passwordless sudo, which
# is abuild's standard setup. The package version comes from the
# checkout's version file, and a throwaway signing key is made when
# the user has none. Writes tigris-<version>-r0.apk (and tigris-doc)
# into OUTDIR (default: the checkout). Needs abuild, tar and gzip.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
OUT=${1:-$TIGER}

[ "`id -u`" = 0 ] && { echo "mkapk.sh: run as a non-root user (abuild refuses root)"; exit 1; }
for t in abuild tar gzip; do
  command -v $t >/dev/null 2>&1 || { echo "mkapk.sh: $t is needed"; exit 1; }
done
[ -d "$OUT" ] || { echo "mkapk.sh: $OUT is not a directory"; exit 1; }

VERSION=`cat "$TIGER/version"`
W=`mktemp -d`
trap 'rm -rf "$W"' 0
mkdir "$W/build"
cp "$TIGER/packaging/APKBUILD" "$TIGER/packaging/tigris.post-upgrade" "$W/build/"
sed -i "s/^pkgver=.*/pkgver=$VERSION/" "$W/build/APKBUILD"
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | gzip > "$W/build/tigris-$VERSION.tar.gz"
cd "$W/build" || exit 1
abuild checksum >/dev/null || exit 1
ls ~/.abuild/*.rsa >/dev/null 2>&1 || abuild-keygen -a -n -q || exit 1
sudo cp ~/.abuild/*.rsa.pub /etc/apk/keys/ || exit 1
touch "$W/before"
abuild -r || exit 1
APK=`find "$HOME/packages" -name 'tigris-[0-9]*.apk' -newer "$W/before" 2>/dev/null | head -1`
[ -n "$APK" ] && [ -f "$APK" ] || { echo "mkapk.sh: no package built"; exit 1; }
find "$HOME/packages" -name 'tigris-*.apk' -newer "$W/before" -exec cp {} "$OUT/" \; || exit 1
ls "$OUT"/tigris-*.apk
