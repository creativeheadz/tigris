#!/bin/sh
#
# packaging/mkapk.sh - an .apk of this checkout, for CI and testing
#
#   sh packaging/mkapk.sh [--throwaway-key | --release] [OUTDIR]
#
# Runs as a non-root user on Alpine (abuild refuses root): CI creates
# the builder first, in the abuild group with passwordless sudo, which
# is abuild's standard setup. The package version comes from the
# checkout's version file. The signing key is never made silently:
# without a flag the build needs a key already in ~/.abuild (as the
# maintainer's release setup leaves it); --throwaway-key makes a
# throwaway key when the user has none (development and CI only);
# --release additionally proves the key is the maintainer's, whose
# public half is committed under packaging/keys
# (doc/release-signing.md). Writes tigris-<version>-r0.apk (and
# tigris-doc) into OUTDIR (default: the checkout). Needs abuild, tar
# and gzip.
#
# 11/10/2026 - No silent throwaway keys: the old script keygenned one
#             whenever the user had none, so a release .apk could be
#             signed by a key nobody can name. The key is explicit now.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
MODE=dev
case "$1" in
  --throwaway-key) MODE=throwaway; shift;;
  --release) MODE=release; shift;;
  --*) echo "mkapk.sh: unknown flag $1"; exit 1;;
esac
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
case "$MODE" in
release)
  # A release .apk is signed by the maintainer's key and no other:
  # its public half must be committed, the private half must be in
  # place (offline with the maintainer, or a CI secret written to
  # ~/.abuild), and the two must be the same key. Never a keygen.
  ls "$TIGER"/packaging/keys/*.rsa.pub >/dev/null 2>&1 || { echo "mkapk.sh: no maintainer key under packaging/keys (doc/release-signing.md)"; exit 1; }
  ls ~/.abuild/*.rsa >/dev/null 2>&1 || { echo "mkapk.sh: --release needs the maintainer key in ~/.abuild (doc/release-signing.md)"; exit 1; }
  MATCH=
  for k in "$TIGER"/packaging/keys/*.rsa.pub; do
    [ -f "$k" ] || continue
    for h in ~/.abuild/*.rsa.pub; do
      [ -f "$h" ] || continue
      cmp -s "$k" "$h" && MATCH=$h
    done
  done
  [ -n "$MATCH" ] || { echo "mkapk.sh: no ~/.abuild key matches packaging/keys"; exit 1; }
  sudo cp "$MATCH" /etc/apk/keys/ || exit 1
  ;;
throwaway)
  ls ~/.abuild/*.rsa >/dev/null 2>&1 || abuild-keygen -a -n -q || exit 1
  sudo cp ~/.abuild/*.rsa.pub /etc/apk/keys/ || exit 1
  ;;
*)
  ls ~/.abuild/*.rsa >/dev/null 2>&1 || { echo "mkapk.sh: no abuild key in ~/.abuild: pass --throwaway-key for a development key, --release for the maintainer build (doc/release-signing.md)"; exit 1; }
  sudo cp ~/.abuild/*.rsa.pub /etc/apk/keys/ || exit 1
  ;;
esac
touch "$W/before"
abuild -r || exit 1
APK=`find "$HOME/packages" -name 'tigris-[0-9]*.apk' -newer "$W/before" 2>/dev/null | head -1`
[ -n "$APK" ] && [ -f "$APK" ] || { echo "mkapk.sh: no package built"; exit 1; }
find "$HOME/packages" -name 'tigris-*.apk' -newer "$W/before" -exec cp {} "$OUT/" \; || exit 1
ls "$OUT"/tigris-*.apk
