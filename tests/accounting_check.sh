#!/bin/sh
#
# tests/accounting_check.sh - check_accounting on offline roots
#
# Seven roots: sysstat collecting (fresh data); sysstat installed
# with stale data; sysstat installed with no data dir at all;
# sysstat explicitly disabled; snoopy preloaded; snoopy configured
# but not preloaded; and an empty root, where neither is installed
# and nothing is said. INFO findings only show with
# Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the fixtures
# read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_accounting with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_accounting ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

F=$W/fresh; mkdir -p "$F/etc" "$F/etc/default" "$F/usr/bin" "$F/var/log/sysstat"
printf '#!/bin/sh\n' > "$F/usr/bin/sar"; chmod 755 "$F/usr/bin/sar"
printf 'ENABLED="true"\n' > "$F/etc/default/sysstat"
printf 'sysstat\n' > "$F/var/log/sysstat/sa16"
run "$F" "$W/out"
has '--INFO-- [aud006i]' "$W/out" &&
has 'data in /var/log/sysstat' "$W/out" &&
! grep -q 'aud005w' "$W/out" &&
  ok "fresh data: inventory only" || { bad "fresh"; cat "$W/out"; }

S=$W/stale; mkdir -p "$S/etc" "$S/etc/cron.d" "$S/var/log/sysstat"
printf '0 * * * * root /usr/lib/sysstat/debian-sa1 1 1\n' > "$S/etc/cron.d/sysstat"
printf 'sysstat\n' > "$S/var/log/sysstat/sa01"
touch -t 202001010000 "$S/var/log/sysstat/sa01"
run "$S" "$W/out"
has '--WARN-- [aud005w]' "$W/out" &&
! grep -q 'aud006i' "$W/out" &&
  ok "stale data: aud005w" || { bad "stale"; cat "$W/out"; }

N=$W/nodata; mkdir -p "$N/etc" "$N/etc/default" "$N/usr/bin"
printf '#!/bin/sh\n' > "$N/usr/bin/sar"; chmod 755 "$N/usr/bin/sar"
printf 'ENABLED="true"\n' > "$N/etc/default/sysstat"
run "$N" "$W/out"
has '--WARN-- [aud005w]' "$W/out" &&
  ok "installed, no data dir: aud005w" || { bad "nodata"; cat "$W/out"; }

O=$W/off; mkdir -p "$O/etc" "$O/etc/default" "$O/usr/bin"
printf '#!/bin/sh\n' > "$O/usr/bin/sar"; chmod 755 "$O/usr/bin/sar"
printf 'ENABLED="false"\n' > "$O/etc/default/sysstat"
run "$O" "$W/out"
[ -s "$W/out" ] && { bad "off"; cat "$W/out"; } ||
  ok "explicitly disabled: nothing said"

P=$W/preloaded; mkdir -p "$P/etc" "$P/usr/lib/x86_64-linux-gnu"
printf '[snoopy]\noutput = syslog\n' > "$P/etc/snoopy.ini"
printf '/usr/lib/x86_64-linux-gnu/libsnoopy.so\n' > "$P/usr/lib/x86_64-linux-gnu/libsnoopy.so"
printf '/usr/lib/x86_64-linux-gnu/libsnoopy.so\n' > "$P/etc/ld.so.preload"
run "$P" "$W/out"
has '--INFO-- [aud008i]' "$W/out" &&
! grep -q 'aud007w' "$W/out" &&
  ok "snoopy preloaded: inventory only" || { bad "preloaded"; cat "$W/out"; }

C=$W/configured; mkdir -p "$C/etc"
printf '[snoopy]\noutput = syslog\n' > "$C/etc/snoopy.ini"
run "$C" "$W/out"
has '--WARN-- [aud007w]' "$W/out" &&
! grep -q 'aud008i' "$W/out" &&
  ok "snoopy configured, not preloaded: aud007w" || { bad "configured"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "neither installed: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
