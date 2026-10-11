#!/bin/sh
#
# tests/logfiles_sunos_check.sh - SunOS check_logfiles on offline roots
#
# Three legs: a world-writable messages log (logf005f) with a
# world-readable audit trail (logf009w); a 644 log with a 600
# trail (silent); and no logs at all (absence is a
# configuration, silent). Runs as a user and as root; the
# fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_logfiles with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/SunOS/default/check_logfiles ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad
mkdir -p "$B/etc" "$B/var/adm" "$B/var/audit"
touch "$B/var/adm/messages" "$B/var/adm/sulog"
chmod 666 "$B/var/adm/messages"
chmod 640 "$B/var/adm/sulog"
touch "$B/var/audit/20261009000000.20261009120000"
chmod 644 "$B/var/audit/20261009000000.20261009120000"
run "$B" "$W/out"
has '--FAIL-- [logf005f]' "$W/out" &&
has 'messages' "$W/out" &&
has '--WARN-- [logf009w]' "$W/out" &&
  ok "writable log, readable trail: both" || { bad "bad"; cat "$W/out"; }

T=$W/tight
mkdir -p "$T/etc" "$T/var/adm" "$T/var/audit"
touch "$T/var/adm/messages"
chmod 644 "$T/var/adm/messages"
touch "$T/var/audit/20261009000000.20261009120000"
chmod 600 "$T/var/audit/20261009000000.20261009120000"
run "$T" "$W/out"
empty "$W/out" &&
  ok "644 log, 600 trail: silent" || { bad "tight noisy"; cat "$W/out"; }

E=$W/emptyroot; mkdir -p "$E/etc"
run "$E" "$W/out"
empty "$W/out" &&
  ok "no logs: silent" || { bad "empty noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
