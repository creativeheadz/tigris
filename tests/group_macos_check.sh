#!/bin/sh
#
# tests/group_macos_check.sh - MacOSX check_group on dslocal roots
#
# Three legs: a loose root (a second wheel name and gid);
# a tight root (wheel and staff alone); and a live leg through
# the dscl stub. Runs as a user and as root; the fixtures read
# the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
umask 022
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_group with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/MacOSX/default/check_group ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }
groups() {  # groups ROOT [EXCEPT...]: the dslocal group fixtures, minus any named
  mkdir -p "$1/etc" "$1/var/db/dslocal/nodes/Default/groups"
  for f in "$TIGER"/tests/fixtures/macos/dsgroups/*.plist
  do
    skip=
    for x in "$@"; do [ "${f##*/}" = "$x" ] && skip=1; done
    [ -n "$skip" ] || cp "$f" "$1/var/db/dslocal/nodes/Default/groups/"
  done
}

B=$W/bad; groups "$B"
run "$B" "$W/out"
has '--WARN-- [grp001w]' "$W/out" &&
has '--WARN-- [grp002w]' "$W/out" &&
has 'dup' "$W/out" &&
  ok "dup name and gid: both" || { bad "bad"; cat "$W/out"; }

T=$W/tight; groups "$T" dup1.plist dup2.plist
run "$T" "$W/out"
empty "$W/out" &&
  ok "wheel and staff: silent" || { bad "tight noisy"; cat "$W/out"; }

echo "Tigris_Dscl_Cmd='$W/tests/fixtures/macos/dscl-stub'" >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/MacOSX/default/check_group ) 2>&1 |
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out" || true
sed -i '$d' "$W/tigris.conf"
empty "$W/out" &&
  ok "dscl stub wheel and staff: silent" || { bad "live noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
