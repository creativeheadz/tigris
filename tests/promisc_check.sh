#!/bin/sh
#
# tests/promisc_check.sh - check_promisc against a sysfs of its own
#
# A fake /sys/class/net: eth0 with the promiscuous bit set (0x1103),
# lo and wlan0 without it, and an interface with no flags file at all.
# Then an empty sysfs (a bare container: nothing to judge) and a tree
# with only short flag values, which cannot carry bit 0x100. Runs as a
# user and as root; the flags files read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run SYS OUTFILE: check_promisc against SYS as /sys
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$1'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_promisc ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$W/out"; }

S=$W/sys/sys/class/net
mkdir -p "$S/eth0" "$S/lo" "$S/wlan0" "$S/tun0"
printf '0x1103' > "$S/eth0/flags"
printf '0x49' > "$S/lo/flags"
printf '0x1003' > "$S/wlan0/flags"
run "$W/sys" "$W/out"

has "[prom001w] Interface \`eth0' is in promiscuous mode:" &&
  ok "a promiscuous interface: prom001w" || { bad "eth0"; cat "$W/out"; }
grep -q 'lo\|wlan0\|tun0' "$W/out" && { bad "clean"; cat "$W/out"; } ||
  ok "loopback, a non-promiscuous wireless and a flagless tunnel: nothing"
grep -q "$W" "$W/out" && bad "a finding names where the sysfs is on this host" || ok "findings name interfaces, not paths"

# a bare container: no class/net, nothing to judge
E=$W/empty
mkdir -p "$E"
run "$E" "$W/empty.out"
[ -s "$W/empty.out" ] && { bad "empty"; cat "$W/empty.out"; } || ok "no sysfs: nothing"

# short flag values cannot carry bit 0x100
T=$W/tiny/sys/class/net
mkdir -p "$T/eth0"
printf '0x3' > "$T/eth0/flags"
run "$W/tiny" "$W/tiny.out"
grep -q 'prom001w' "$W/tiny.out" && { bad "tiny"; cat "$W/tiny.out"; } || ok "a short flags value: nothing"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
