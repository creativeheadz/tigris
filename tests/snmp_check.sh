#!/bin/sh
#
# tests/snmp_check.sh - check_snmp on offline roots
#
# Four roots: open defaults (an unrestricted write community plus
# public on read); a write community narrowed to the manager (with a
# com2sec default riding along); SNMPv3 users only; and an empty
# root, where the daemon is not configured and nothing is said. INFO
# findings only show with Tiger_Show_INFO_Msgs=Y. Runs as a user and
# as root; the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_snmp with ROOT as the audited system
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_snmp ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/bad; mkdir -p "$B/etc/snmp"
cat > "$B/etc/snmp/snmpd.conf" <<'EOF'
# open to the world, as shipped in too many examples
rocommunity public
rwcommunity private
EOF
run "$B" "$W/out"
has "--WARN-- [snmp001w] SNMP answers a write community ('\`private')" "$W/out" &&
has "--INFO-- [snmp003i] SNMP uses a default community string ('\`public')" "$W/out" &&
has "--INFO-- [snmp003i] SNMP uses a default community string ('\`private')" "$W/out" &&
  ok "open defaults: snmp001w plus both defaults" || { bad "bad"; cat "$W/out"; }

N=$W/narrow; mkdir -p "$N/etc/snmp"
cat > "$N/etc/snmp/snmpd.conf" <<'EOF'
rwcommunity monsecret 10.0.0.5
com2sec mgmt 10.0.0.5 public
EOF
run "$N" "$W/out"
has "--INFO-- [snmp002i] SNMP answers a write community ('\`monsecret')" "$W/out" &&
! grep -q 'snmp001w' "$W/out" &&
has "--INFO-- [snmp003i] SNMP uses a default community string ('\`public')" "$W/out" &&
  ok "a narrowed write community: only snmp002i, com2sec default found" || { bad "narrow"; cat "$W/out"; }

# "default" and 0.0.0.0/0 as the source are the whole network, and
# rwcommunity6 is a write community as much as rwcommunity
A=$W/anysrc; mkdir -p "$A/etc/snmp"
printf 'rwcommunity s3cret default\nrwcommunity w1de 0.0.0.0/0\nrwcommunity6 six ::/0\n' > "$A/etc/snmp/snmpd.conf"
run "$A" "$W/out"
has "--WARN-- [snmp001w] SNMP answers a write community ('\`s3cret')" "$W/out" &&
has "--WARN-- [snmp001w] SNMP answers a write community ('\`w1de')" "$W/out" &&
has "--WARN-- [snmp001w] SNMP answers a write community ('\`six')" "$W/out" &&
! grep -q 'snmp002i' "$W/out" &&
  ok "a source of default, 0.0.0.0/0 or ::/0, and rwcommunity6: snmp001w" || { bad "any source"; cat "$W/out"; }

V=$W/v3; mkdir -p "$V/etc/snmp"
cat > "$V/etc/snmp/snmpd.conf" <<'EOF'
rouser monitor auth
rwuser admin priv
EOF
run "$V" "$W/out"
grep -q 'snmp001w\|snmp002i\|snmp003i' "$W/out" && { bad "v3"; cat "$W/out"; } ||
  ok "SNMPv3 users only: nothing"

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no snmpd.conf: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
