#!/bin/sh
#
# tests/pkg_bsd_check.sh - FreeBSD check_pkg against pkg stubs
#
# Three legs: update notices touching installed packages
# (upd006w); a clean pkg (silent); and under --root, where the
# check stays silent (the database is the running machine's,
# never a root's). Runs as a user and as root; the live legs
# read the same for both.
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
run() {  # run FIXTURE OUTFILE [ROOT]: check_pkg with the stub
  echo "Tiger_Pkg_Cmd='$W/tests/fixtures/bsd/$1'" >> "$W/tigerrc"
  if [ -n "$3" ]; then
    ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$3" sh ./systems/FreeBSD/default/check_pkg ) 2>&1
  else
    ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/FreeBSD/default/check_pkg ) 2>&1
  fi |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
  sed -i '$d' "$W/tigerrc"
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

run pkg-notices "$W/out"
has '--WARN-- [upd006w]' "$W/out" &&
  ok "update notices: upd006w" || { bad "notices"; cat "$W/out"; }

run pkg-clean "$W/out"
empty "$W/out" &&
  ok "clean pkg: silent" || { bad "clean noisy"; cat "$W/out"; }

R=$W/root; mkdir -p "$R/etc"
run pkg-notices "$W/out" "$R"
empty "$W/out" &&
  ok "offline root: silent" || { bad "root noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
