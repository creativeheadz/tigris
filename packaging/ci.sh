#!/bin/sh
#
# packaging/ci.sh - build, install and smoke-test one format
#
#   sh packaging/ci.sh deb|rpm|apk|aur OUTDIR
#
# Runs as root in the format's container (CI mounts the checkout
# read-only at /tiger and an output dir at OUTDIR): installs the
# build tools, builds with packaging/mk*, installs the package and
# runs packaging/smoke-installed.sh. The .deb job also installs
# Debian's tiger beside it. The aur job builds from a tarball of the
# tree (never the tag: on a release commit CI may run before the tag
# exists) and checks the committed .SRCINFO still matches. Every job
# also runs the release signature self-test (verify-sigs.sh), so the
# verify path users get is exercised on all four formats.
#
# 11/10/2026 - The apk build passes --throwaway-key (mkapk.sh makes no
#             key silently any more), and every format run ends proving
#             the release checksums and signatures verify.
#
FMT=${1:?usage: ci.sh deb|rpm|apk|aur OUTDIR}
OUT=${2:?usage: ci.sh deb|rpm|apk|aur OUTDIR}
TIGER=/tiger
[ -d "$TIGER/packaging" ] || { echo "ci.sh: mount the checkout at /tiger"; exit 1; }
mkdir -p "$OUT"

case "$FMT" in
deb)
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dpkg-dev gcc make file || exit 1
  sh "$TIGER/packaging/mkdeb.sh" "$OUT" || exit 1
  dpkg -i "$OUT"/tigris_*.deb || exit 1
  sh "$TIGER/packaging/smoke-installed.sh" || exit 1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tiger || exit 1
  dpkg -l tiger tigris | grep -q '^ii  tiger' || { echo "ci.sh: tiger missing"; exit 1; }
  dpkg -l tiger tigris | grep -q '^ii  tigris' || { echo "ci.sh: tigris missing"; exit 1; }
  for b in tiger tigris tigris-diff tigris-export tigris-accept; do
    command -v $b >/dev/null || { echo "ci.sh: $b not on PATH"; exit 1; }
  done
  ;;
rpm)
  dnf install -y -q rpm-build gcc make tar gzip diffutils file findutils || exit 1
  sh "$TIGER/packaging/mkrpm.sh" "$OUT" || exit 1
  # --nosignature: rpm 6 refuses unsigned installs, and this .rpm is
  # deliberately unsigned (its trust is the detached .asc beside the
  # release's SHA256SUMS, which the release proves). It was just built
  # here from the mounted tree, so there is nothing to authenticate.
  rpm -i --nosignature "$OUT"/tigris-[0-9]*.rpm || exit 1
  sh "$TIGER/packaging/smoke-installed.sh" || exit 1
  ;;
apk)
  apk add -q abuild tar gzip sudo openssl || exit 1
  adduser -D builder 2>/dev/null
  addgroup builder abuild
  echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
  chmod 777 "$OUT"
  KEYFLAG=--throwaway-key
  if [ -n "${TIGRIS_APK_RELEASE:-}" ]; then
    # A release .apk: the maintainer's private half arrives as a
    # mounted file (never in the tree). abuild names the signature
    # in the package after the public half beside the private key,
    # and apk matches that name against its trusted keys, so the
    # private half is staged under the name of the committed public
    # half it belongs to — proven with openssl, not assumed. A key
    # whose public half is not committed fails closed here, and
    # abuild signs only with PACKAGER_PRIVKEY (abuild-keygen -a
    # writes it; there is no keygen on this path, so it is written
    # here). (doc/release-signing.md).
    KEYFLAG=--release
    KEYFILE=${TIGRIS_ABUILD_KEY_FILE:?ci.sh: TIGRIS_APK_RELEASE needs TIGRIS_ABUILD_KEY_FILE}
    [ -f "$KEYFILE" ] || { echo "ci.sh: $KEYFILE is not a file"; exit 1; }
    mkdir -p /home/builder/.abuild
    cp "$TIGER"/packaging/keys/*.rsa.pub /home/builder/.abuild/ || exit 1
    PRIVPUB=`openssl rsa -in "$KEYFILE" -pubout 2>/dev/null` || { echo "ci.sh: $KEYFILE is no RSA private key"; exit 1; }
    KEYNAME=
    for p in /home/builder/.abuild/*.rsa.pub; do
      [ "`openssl rsa -pubin -in "$p" -outform PEM 2>/dev/null`" = "$PRIVPUB" ] && KEYNAME=${p##*/}
    done
    [ -n "$KEYNAME" ] || { echo "ci.sh: the release key matches no committed packaging/keys pub"; exit 1; }
    cp "$KEYFILE" "/home/builder/.abuild/${KEYNAME%.pub}"
    printf 'PACKAGER_PRIVKEY="/home/builder/.abuild/%s"\n' "${KEYNAME%.pub}" > /home/builder/.abuild/abuild.conf
    chown -R builder /home/builder/.abuild
    chmod 600 "/home/builder/.abuild/${KEYNAME%.pub}"
  fi
  su builder -c "sh $TIGER/packaging/mkapk.sh $KEYFLAG $OUT" || exit 1
  apk add -q --allow-untrusted "$OUT"/tigris-*.apk || exit 1
  sh "$TIGER/packaging/smoke-installed.sh" || exit 1
  ;;
aur)
  pacman -Sy --noconfirm -q base-devel sudo || exit 1
  useradd -m builder
  echo 'builder ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
  mkdir -p /build && chown builder /build
  VERSION=`cat "$TIGER/version"`
  TAG=version_`echo "$VERSION" | tr . _`
  ( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run \
    --transform "s,^,tigris-$TAG/,SH" -cf - . ) | gzip > "/build/tigris-$VERSION.tar.gz"
  cp "$TIGER/packaging/PKGBUILD" "$TIGER/packaging/tigris.install" /build/ && chown builder /build/PKGBUILD /build/tigris.install
  su builder -c "cd /build && sed -i 's|^source=.*|source=(tigris-$VERSION.tar.gz)|; s|^sha256sums=.*|sha256sums=(SKIP)|' PKGBUILD && makepkg -s --noconfirm" || exit 1
  cp /build/tigris-[0-9]*.pkg.tar.* "$OUT/" || exit 1
  mkdir -p /srcinfo && cp "$TIGER/packaging/PKGBUILD" "$TIGER/packaging/tigris.install" /srcinfo/ && chown -R builder /srcinfo
  su builder -c "cd /srcinfo && makepkg --printsrcinfo" | diff - "$TIGER/packaging/.SRCINFO" || { echo "ci.sh: .SRCINFO does not match PKGBUILD"; exit 1; }
  pacman -U --noconfirm "$OUT"/tigris-[0-9]*.pkg.tar.* >/dev/null || exit 1
  sh "$TIGER/packaging/smoke-installed.sh" || exit 1
  ;;
*)
  echo "ci.sh: unknown format $FMT"; exit 1;;
esac

# The verify path ships in the source tree, not the installed package,
# so smoke-installed.sh cannot run it: ci.sh does, on every format,
# with throwaway fixtures and keys (no secrets).
sh "$TIGER/packaging/verify-sigs.sh" --self-test || exit 1

echo "ci.sh: $FMT passed"
