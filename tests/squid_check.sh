#!/bin/sh
#
# tests/squid_check.sh - check_squid on offline roots
#
# Four roots: wide open (allow all, no port lock, a readable
# cachemgr password); tight (named networks, Safe_ports denied, no
# secrets); the open config locked down to root (no squid003w); and
# an empty root, where there is no proxy and nothing is said. Runs
# as a user and as root; the fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_squid with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_squid ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/bad; mkdir -p "$B/etc/squid"
cat > "$B/etc/squid/squid.conf" <<'EOF'
acl localnet src 10.0.0.0/8
http_access allow all
cachemgr_passwd secret all
EOF
chmod 644 "$B/etc/squid/squid.conf"
run "$B" "$W/out"
has '--WARN-- [squid001w]' "$W/out" &&
has '--WARN-- [squid002w]' "$W/out" &&
has '--WARN-- [squid003w]' "$W/out" &&
  ok "open proxy, no port lock, readable password: all three" || { bad "bad"; cat "$W/out"; }

T=$W/tight; mkdir -p "$T/etc/squid"
cat > "$T/etc/squid/squid.conf" <<'EOF'
acl localnet src 10.0.0.0/8
acl Safe_ports port 80 443
acl SSL_ports port 443
http_access deny !Safe_ports
http_access allow localnet
http_access deny all
EOF
run "$T" "$W/out"
grep -q 'squid001w\|squid002w\|squid003w' "$W/out" && { bad "tight"; cat "$W/out"; } ||
  ok "named networks with a port lock: nothing"

L=$W/locked; mkdir -p "$L/etc/squid"
cp "$B/etc/squid/squid.conf" "$L/etc/squid/squid.conf"
chmod 600 "$L/etc/squid/squid.conf"
run "$L" "$W/out"
has '--WARN-- [squid001w]' "$W/out" &&
has '--WARN-- [squid002w]' "$W/out" &&
! grep -q 'squid003w' "$W/out" &&
  ok "the open config locked down: no squid003w" || { bad "locked"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no squid.conf: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
