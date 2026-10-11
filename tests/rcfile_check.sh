#!/bin/sh
#
# tests/rcfile_check.sh - a tigerrc named with -c is checked like a found one
#
# config reads a configuration file as shell code, as root, so a found
# one is skipped when its group or others may write it or someone else
# owns it (con003c, con015c). A file named with -c got no such check
# until October 2026. Now it does, and since there is nothing to fall
# back to the run stops (con016e): this names a group-writable tigerrc
# with -c and expects exit 1, the message, and no report; then the same
# file at 0600 and expects a run. Needs no root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

sed 's/^\(Tiger_\(Check\|Run\|Deb\)_[A-Za-z0-9_]*\)=.*/\1=N/' "$W/tigerrc" > "$W/rc.t"

chmod 664 "$W/rc.t"
( cd "$W" && sh ./tigris -q -c rc.t ) > "$W/out" 2>&1
st=$?
[ "$st" = 1 ] && ok "a group-writable -c file: exit 1" || bad "exit $st with a group-writable -c file"
grep -q 'con003c' "$W/out" && grep -q 'con016e' "$W/out" && ok "con003c says why and con016e says the run stopped" || { bad "messages"; cat "$W/out"; }
[ -z "`ls "$W"/log/security.report.* 2>/dev/null`" ] && ok "no report was written" || bad "a report was written"

chmod 600 "$W/rc.t"
( cd "$W" && sh ./tigris -q -c rc.t ) > "$W/out" 2>&1
st=$?
[ "$st" = 0 ] && ok "the same file at 0600: a run, exit 0" || { bad "exit $st at 0600"; cat "$W/out"; }
grep -q 'con016e' "$W/out" && bad "con016e at 0600" || ok "no con016e at 0600"

# the preset ./tigerrc, group-writable: skipped with con003c, no stop
chmod 664 "$W/tigerrc"
( cd "$W" && TIGERHOMEDIR=$W sh ./config -t ) > "$W/out" 2>&1
grep -q 'con003c.*tigerrc' "$W/out" && ok "a group-writable preset tigerrc: con003c" || { bad "no con003c for the preset"; head -5 "$W/out"; }
grep -q 'con016e' "$W/out" && bad "con016e for the preset" || ok "the preset does not stop the run"
[ "`grep -c 'con003c' "$W/out"`" = 1 ] && ok "said once" || bad "con003c `grep -c con003c "$W/out"` times"
chmod 644 "$W/tigerrc"

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
