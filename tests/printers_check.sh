#!/bin/sh
#
# tests/printers_check.sh - check_printers on offline roots
#
# Four roots: exposed (browsing on, listening past localhost, a
# password in a device URI left readable); tight (localhost only,
# no browsing, a passwordless URI); the exposed config locked down
# to root (no print003w); and an empty root, where there is no
# printing and nothing is said. Runs as a user and as root; the
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
run() {  # run ROOT OUTFILE: check_printers with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_printers ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/bad; mkdir -p "$B/etc/cups"
cat > "$B/etc/cups/cupsd.conf" <<'EOF'
Browsing On
Listen *:631
Listen /run/cups/cups.sock
<Policy default>
  JobPrivateAccess default
</Policy>
EOF
cat > "$B/etc/cups/printers.conf" <<'EOF'
<Printer Office>
DeviceURI ipp://printop:s3cret@print.example.com/printers/Office
State Idle
</Printer>
EOF
chmod 644 "$B/etc/cups/cupsd.conf" "$B/etc/cups/printers.conf"
run "$B" "$W/out"
has '--WARN-- [print001w]' "$W/out" &&
has '--WARN-- [print002w]' "$W/out" &&
has '--WARN-- [print003w]' "$W/out" &&
  ok "browsing, network listen, URI password: all three" || { bad "bad"; cat "$W/out"; }

T=$W/tight; mkdir -p "$T/etc/cups"
cat > "$T/etc/cups/cupsd.conf" <<'EOF'
Browsing Off
Listen localhost:631
Listen /run/cups/cups.sock
EOF
cat > "$T/etc/cups/printers.conf" <<'EOF'
<Printer Office>
DeviceURI socket://print.example.com:9100
State Idle
</Printer>
EOF
run "$T" "$W/out"
grep -q 'print001w\|print002w\|print003w' "$W/out" && { bad "tight"; cat "$W/out"; } ||
  ok "localhost, no browsing, passwordless URI: nothing"

L=$W/locked; mkdir -p "$L/etc/cups"
cp "$B/etc/cups/cupsd.conf" "$L/etc/cups/cupsd.conf"
cp "$B/etc/cups/printers.conf" "$L/etc/cups/printers.conf"
chmod 600 "$L/etc/cups/cupsd.conf" "$L/etc/cups/printers.conf"
run "$L" "$W/out"
has '--WARN-- [print001w]' "$W/out" &&
has '--WARN-- [print002w]' "$W/out" &&
! grep -q 'print003w' "$W/out" &&
  ok "the exposed config locked down: no print003w" || { bad "locked"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no CUPS config files: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
