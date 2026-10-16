#!/bin/sh
#
# tests/firewall_bsd_check.sh - FreeBSD check_firewall against stubs
#
# Five legs: pf off with ipfw rules (ipfw covers, silent); pf on
# with no rules (the empty ruleset is named); pf on with rules
# (silent); pf off with ipfw open (neither filters); and under
# --root, where the check stays silent (the ruleset is the
# running machine's, never a root's). Runs as a user and as
# root; the live legs read the same for both.
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
run() {  # run PF IPFW OUTFILE [ROOT]: check_firewall with the stubs
  echo "Tigris_Pfctl_Cmd='$W/tests/fixtures/bsd/$1'" >> "$W/tigris.conf"
  echo "Tigris_Ipfw_Cmd='$W/tests/fixtures/bsd/$2'" >> "$W/tigris.conf"
  if [ -n "$4" ]; then
    ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$4" sh ./systems/FreeBSD/default/check_firewall ) 2>&1
  else
    ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/FreeBSD/default/check_firewall ) 2>&1
  fi |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$3" || true
  sed -i '$d;$d' "$W/tigris.conf"
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }
nfind() { grep -cF -- '--WARN-- [fire' "$1"; }

run pf-off ipfw-rules "$W/out"
empty "$W/out" &&
  ok "pf off, ipfw ruled: ipfw covers" || { bad "pf-off"; cat "$W/out"; }

run pf-empty ipfw-open "$W/out"
[ "`nfind "$W/out"`" -eq 2 ] &&
has 'empty ruleset' "$W/out" &&
  ok "pf empty: one voice" || { bad "pf-empty"; cat "$W/out"; }

run pf-rules ipfw-open "$W/out"
empty "$W/out" &&
  ok "pf ruled: silent" || { bad "rules noisy"; cat "$W/out"; }

run pf-off ipfw-open "$W/out"
[ "`nfind "$W/out"`" -eq 2 ] &&
has 'Nothing filters' "$W/out" &&
has 'ipfw runs its stock allow-all' "$W/out" &&
  ok "both open: one voice" || { bad "open"; cat "$W/out"; }

R=$W/root; mkdir -p "$R/etc"
run pf-off ipfw-open "$W/out" "$R"
empty "$W/out" &&
  ok "offline root: silent" || { bad "root noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
