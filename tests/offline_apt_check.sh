#!/bin/sh
#
# tests/offline_apt_check.sh - apt reads an offline root's packages, never
# its configuration, and never this host's files
#
# check_updates asks this host's apt-get, in simulation, which security
# updates an offline root is waiting for. Until October 2026 it pointed
# apt at the root with Dir, so apt read the root's apt.conf.d too, and an
# apt.conf.d can name programs apt runs; and apt opened the root's files
# by their paths, following the root's links onto this host. A root made
# by hand, so no network is needed: one package installed at 1.0, a
# security list offering 2.0, and an apt.conf.d that, read, would point
# apt at lists that do not exist (so the update would go unseen). A
# second root's dpkg status is a link that climbs out of it to a status
# file on this host, which must not be read. Skips when apt-get is not
# here.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
command -v apt-get >/dev/null 2>&1 || { echo "ok   (no apt-get here: nothing to test)"; echo PASS; exit 0; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
uid=`id -u`
[ "$uid" = 0 ] && chown -R 0:0 "$W"

# root ROOT: the hand-made system
root()
{
  mkdir -p "$1/etc/apt/apt.conf.d" "$1/etc/apt/sources.list.d" "$1/var/lib/dpkg/info" "$1/var/lib/apt/lists"
  printf 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\nNAME="Debian GNU/Linux"\nVERSION_ID="12"\nID=debian\n' > "$1/etc/os-release"
  echo 12.0 > "$1/etc/debian_version"
  echo 'deb http://deb.example.org/debian stable-security main' > "$1/etc/apt/sources.list"
  l=$1/var/lib/apt/lists/deb.example.org_debian_dists_stable-security
  cat > "${l}_Release" <<'EOF'
Origin: Debian
Label: Debian-Security
Suite: stable-security
Codename: zz
Architectures: amd64
Components: main
EOF
  cat > "${l}_main_binary-amd64_Packages" <<'EOF'
Package: zz-tiger-sec
Version: 2.0
Architecture: amd64
Maintainer: Tigris <tigris@example.org>
Filename: pool/main/z/zz-tiger-sec_2.0_amd64.deb
Size: 1
MD5sum: 00000000000000000000000000000000
Description: a package with a security update

EOF
}
status()
{
  cat <<'EOF'
Package: dpkg
Status: install ok installed
Architecture: amd64
Version: 1.21.22
Maintainer: Tigris <tigris@example.org>
Description: the package manager

Package: zz-tiger-sec
Status: install ok installed
Architecture: amd64
Version: 1.0
Maintainer: Tigris <tigris@example.org>
Description: a package with a security update

EOF
}

R=$W/img
root "$R"
status > "$R/var/lib/dpkg/status"
# read, this would hide every list from apt
echo 'Dir::State::lists "/nonexistent/";' > "$R/etc/apt/apt.conf.d/99zz-lists"

# the second root: its status climbs out of it, to this host's file
H=$W/host
root "$H"
status > "$W/hoststatus"
ln -s ../../../../hoststatus "$H/var/lib/dpkg/status"

{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Check_SYSTEM=Y'; echo 'Tiger_Check_UPDATES=Y'
  echo 'Tiger_Deb_CheckMD5Sums=N'; echo 'Tiger_Deb_NoPackFiles=N'; echo 'Tiger_Deb_StatOverride=N'
} > "$W/profiles/upd"
chmod 644 "$W/profiles/upd"

run()
{
  rm -f "$W"/log/security.report.*
  ( cd "$W" && sh ./tigris -q --profile upd --root "$1" ) > "$W/out" 2>&1
  report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
  [ -n "$report" ] && cat "$report"
}

run "$R" > "$W/r1"
grep -q 'upd003f.*1 security update' "$W/r1" &&
  ok "the root's security update is found: upd003f" ||
  { bad "no upd003f for the root's update"; sed 's/^/     /' "$W/r1" "$W/out"; }
grep -q 'upd004i' "$W/r1" &&
  bad "upd004i: apt read the root's apt.conf.d (its lists went missing)" ||
  ok "the root's apt.conf.d is not apt's configuration"

run "$H" > "$W/r2"
grep -q 'upd003f' "$W/r2" &&
  bad "upd003f from this host's status file, reached through the root's link" ||
  ok "a status link out of the root reads nothing of this host"

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
