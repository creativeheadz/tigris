#!/bin/sh
#
# tests/filevault_check.sh - check_filevault against fdesetup fixtures
#
# FileVault off reports fde001w; on is silent; and under --root the
# check stays silent (FileVault status is the running Mac's, never
# a root's). Runs as a user and as root; the live legs read the
# same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run FIXTURE OUTFILE [ROOT]: check_filevault with the stub
  echo "Tiger_Fdesetup_Cmd='$W/tests/fixtures/macos/$1'" >> "$W/tigerrc"
  if [ -n "$3" ]; then
    ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$3" sh ./systems/MacOSX/default/check_filevault ) 2>&1
  else
    ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/MacOSX/default/check_filevault ) 2>&1
  fi |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
  sed -i '$d' "$W/tigerrc"
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

run fdesetup-off "$W/out"
has '--WARN-- [fde001w]' "$W/out" &&
  ok "FileVault off: fde001w" || { bad "off"; cat "$W/out"; }

run fdesetup-on "$W/out"
empty "$W/out" &&
  ok "FileVault on: silent" || { bad "on noisy"; cat "$W/out"; }

R=$W/root; mkdir -p "$R/etc"
run fdesetup-off "$W/out" "$R"
empty "$W/out" &&
  ok "offline root: silent" || { bad "root noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
