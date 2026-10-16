#!/bin/sh
#
# tests/firewall_sunos_check.sh - SunOS check_firewall against stubs
#
# Three legs: rules loaded (silent); nothing loaded (fire001w and
# fire002w name the empty ruleset); and under --root, where the
# check stays silent (the ruleset is the running machine's, never
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
run() {  # run STUB OUTFILE [ROOT]: check_firewall with the stub
  echo "Tigris_Ipfstat_Cmd='$W/tests/fixtures/sunos/$1'" >> "$W/tigris.conf"
  if [ -n "$3" ]; then
    ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$3" sh ./systems/SunOS/default/check_firewall ) 2>&1
  else
    ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/SunOS/default/check_firewall ) 2>&1
  fi |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
  sed -i '$d' "$W/tigris.conf"
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

run ipfstat-rules "$W/out"
empty "$W/out" &&
  ok "rules loaded: silent" || { bad "rules noisy"; cat "$W/out"; }

run ipfstat-empty "$W/out"
has '--WARN-- [fire001w]' "$W/out" &&
has '--WARN-- [fire002w]' "$W/out" &&
has 'no active rules' "$W/out" &&
  ok "nothing loaded: fire001w, fire002w" || { bad "empty"; cat "$W/out"; }

R=$W/root; mkdir -p "$R/etc"
run ipfstat-empty "$W/out" "$R"
empty "$W/out" &&
  ok "offline root: silent" || { bad "root noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
