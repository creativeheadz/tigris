#!/bin/sh
#
# tests/passwd_macos_check.sh - MacOSX check_passwd on dslocal roots
#
# Three legs: a loose root (a second uid 0, a second admin name,
# a disabled account with a shell, an unknown shell); a tight
# root (root, one admin, a disabled daemon with /usr/bin/false);
# and a live leg through the dscl stub. Runs as a user and as
# root; the fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_passwd with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/MacOSX/default/check_passwd ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }
shells() {  # shells PATH: an /etc/shells with the stock entries
  mkdir -p "$1/etc"
  printf '%s\n' /bin/sh /bin/bash > "$1/etc/shells"
}
users() {  # users ROOT [EXCEPT...]: the dslocal user fixtures, minus any named
  mkdir -p "$1/var/db/dslocal/nodes/Default/users"
  for f in "$TIGER"/tests/fixtures/macos/dsusers/*.plist
  do
    skip=
    for x in "$@"; do [ "${f##*/}" = "$x" ] && skip=1; done
    [ -n "$skip" ] || cp "$f" "$1/var/db/dslocal/nodes/Default/users/"
  done
}

B=$W/bad; shells "$B"; users "$B"
run "$B" "$W/out"
has '--WARN-- [pass017w]' "$W/out" &&
has 'evil' "$W/out" &&
has '--WARN-- [pass001w]' "$W/out" &&
has '--WARN-- [pass002w]' "$W/out" &&
has '--WARN-- [pass014w]' "$W/out" &&
has 'locked' "$W/out" &&
has '--WARN-- [pass015w]' "$W/out" &&
has 'noshell' "$W/out" &&
  ok "uid 0, dup name, dup uid, disabled shell, bad shell: all five" || { bad "bad"; cat "$W/out"; }

T=$W/tight; shells "$T"; users "$T" evil.plist admin2.plist locked.plist noshell.plist
run "$T" "$W/out"
empty "$W/out" &&
  ok "root, admin, locked daemon: silent" || { bad "tight noisy"; cat "$W/out"; }

echo "Tigris_Dscl_Cmd='$W/tests/fixtures/macos/dscl-stub'" >> "$W/tigris.conf"
# the users come live from the dscl stub, but the valid shells must
# not come live from this host's /etc/shells: Alpine, for one, does
# not list /bin/bash, which would turn pass014w into pass015w
S=$W/stubroot; shells "$S"
( cd "$W" && TIGERHOMEDIR=$W Tigris_Shells_File="$S/etc/shells" sh ./systems/MacOSX/default/check_passwd ) 2>&1 |
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out" || true
sed -i '$d' "$W/tigris.conf"
has '--WARN-- [pass017w]' "$W/out" &&
has 'evil' "$W/out" &&
has '--WARN-- [pass014w]' "$W/out" &&
has '--WARN-- [pass015w]' "$W/out" &&
  ok "dscl stub: uid 0, disabled shell, bad shell" || { bad "live"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
