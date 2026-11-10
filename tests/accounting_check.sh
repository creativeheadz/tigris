#!/bin/sh
#
# tests/accounting_check.sh - check_accounting on offline roots
#
# Nine roots: sysstat collecting (fresh data); sysstat installed
# with stale data; sysstat installed with no data dir at all;
# sysstat explicitly disabled; snoopy preloaded; snoopy's library
# alone (in arm64's directory), not preloaded; snoopy whose
# preload line is commented out; the configuration removed sysstat
# and snoopy packages leave behind, which is not an installation;
# and an empty root, where neither is installed and nothing is
# said. INFO findings only show with
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

S=$W/stale; mkdir -p "$S/etc" "$S/etc/cron.d" "$S/var/log/sysstat" "$S/usr/lib/sysstat"
printf '\177ELF\n' > "$S/usr/lib/sysstat/sadc"; chmod 755 "$S/usr/lib/sysstat/sadc"
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
grep -v '^--INFO-- \[aud009i\]' "$W/out" | grep -q . && { bad "off"; cat "$W/out"; } ||
  ok "explicitly disabled: nothing said about sysstat or snoopy"

P=$W/preloaded; mkdir -p "$P/etc" "$P/usr/lib/x86_64-linux-gnu"
printf '[snoopy]\noutput = syslog\n' > "$P/etc/snoopy.ini"
printf '/usr/lib/x86_64-linux-gnu/libsnoopy.so\n' > "$P/usr/lib/x86_64-linux-gnu/libsnoopy.so"
printf '/usr/lib/x86_64-linux-gnu/libsnoopy.so\n' > "$P/etc/ld.so.preload"
run "$P" "$W/out"
has '--INFO-- [aud008i]' "$W/out" &&
! grep -q 'aud007w' "$W/out" &&
  ok "snoopy preloaded: inventory only" || { bad "preloaded"; cat "$W/out"; }

C=$W/configured; mkdir -p "$C/etc" "$C/usr/lib/aarch64-linux-gnu"
printf '\177ELF\n' > "$C/usr/lib/aarch64-linux-gnu/libsnoopy.so.0.0.0"
run "$C" "$W/out"
has '--WARN-- [aud007w]' "$W/out" &&
! grep -q 'aud008i' "$W/out" &&
  ok "snoopy library alone (arm64's directory), not preloaded: aud007w" || { bad "configured"; cat "$W/out"; }

# ld.so reads '#' to the end of a line as a comment
K=$W/commented; mkdir -p "$K/etc" "$K/usr/lib/x86_64-linux-gnu"
printf '[snoopy]\noutput = syslog\n' > "$K/etc/snoopy.ini"
printf '\177ELF\n' > "$K/usr/lib/x86_64-linux-gnu/libsnoopy.so"
printf '# off while we debug\n#/usr/lib/x86_64-linux-gnu/libsnoopy.so\n' > "$K/etc/ld.so.preload"
run "$K" "$W/out"
has '--WARN-- [aud007w]' "$W/out" &&
! grep -q 'aud008i' "$W/out" &&
  ok "snoopy preload commented out: aud007w, not aud008i" || { bad "commented"; cat "$W/out"; }

# what apt remove (not purge) leaves of both packages
R=$W/removed; mkdir -p "$R/etc/sysstat" "$R/etc/cron.d" "$R/etc/default"
printf 'HISTORY=7\n' > "$R/etc/sysstat/sysstat"
printf '0 * * * * root command -v debian-sa1 > /dev/null && debian-sa1 1 1\n' > "$R/etc/cron.d/sysstat"
printf 'ENABLED="true"\n' > "$R/etc/default/sysstat"
printf '[snoopy]\noutput = syslog\n' > "$R/etc/snoopy.ini"
run "$R" "$W/out"
grep -v '^--INFO-- \[aud009i\]' "$W/out" | grep -q . && { bad "removed"; cat "$W/out"; } ||
  ok "configuration left by removed packages: nothing said about sysstat or snoopy"

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
has '--INFO-- [aud009i] No process accounting (acct, psacct) is installed' "$W/out" && [ "`grep -c . "$W/out"`" = 1 ] &&
  ok "nothing installed: the one INFO that process accounting is not (aud009i)" || { bad "empty"; cat "$W/out"; }

# Process accounting: accton there, then its file, then the service
A=$W/acct; mkdir -p "$A/etc" "$A/usr/sbin"
printf '#!/bin/sh\n' > "$A/usr/sbin/accton"; chmod 755 "$A/usr/sbin/accton"
run "$A" "$W/out"
has '--WARN-- [aud010w] Process accounting is installed but its file is missing' "$W/out" && ! grep -q 'aud009i\|aud011i' "$W/out" &&
  ok "accton with no accounting file: aud010w" || { bad "acct no file"; cat "$W/out"; }
mkdir -p "$A/var/log/account"; : > "$A/var/log/account/pacct"
run "$A" "$W/out"
has '--WARN-- [aud010w] Process accounting is installed and /var/log/account/pacct exists, but no service turns it on at boot' "$W/out" &&
  ok "the file there, nothing enabling it at boot: aud010w" || { bad "acct not enabled"; cat "$W/out"; }
mkdir -p "$A/etc/systemd/system/multi-user.target.wants"
ln -s /usr/lib/systemd/system/acct.service "$A/etc/systemd/system/multi-user.target.wants/acct.service"
run "$A" "$W/out"
has '--INFO-- [aud011i] Process accounting records to /var/log/account/pacct (acct.service enabled).' "$W/out" && ! grep -q 'aud010w\|aud009i' "$W/out" &&
  ok "file and wants link: inventory only (aud011i)" || { bad "acct on"; cat "$W/out"; }
# Fedora's names: psacct.service and /var/account/pacct
Q=$W/psacct; mkdir -p "$Q/etc/systemd/system/multi-user.target.wants" "$Q/usr/sbin" "$Q/var/account"
printf '#!/bin/sh\n' > "$Q/usr/sbin/accton"; chmod 755 "$Q/usr/sbin/accton"; : > "$Q/var/account/pacct"
ln -s /usr/lib/systemd/system/psacct.service "$Q/etc/systemd/system/multi-user.target.wants/psacct.service"
run "$Q" "$W/out"
has '--INFO-- [aud011i] Process accounting records to /var/account/pacct (psacct.service enabled).' "$W/out" &&
  ok "psacct.service and /var/account/pacct, as Fedora has them: aud011i" || { bad "psacct"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
