#!/bin/sh
#
# tests/crontabs_sunos_check.sh - SunOS check_crontabs on offline roots
#
# Two legs: a bad root (a world-writable spool tab, a relative
# command and a group-writable cron.d drop-in), and a tight root
# (locked tabs, full pathnames: silent as root, ownership
# reported as a user, which proves that judgment works).
# Solaris has no /etc/crontab and no periodic. Runs as a user
# and as root; the fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_crontabs with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/SunOS/default/check_crontabs ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad
mkdir -p "$B/etc" "$B/var/spool/cron/crontabs" "$B/etc/cron.d"
printf '0 9 * * * /usr/local/bin/good\n' > "$B/var/spool/cron/crontabs/helen"
chmod 666 "$B/var/spool/cron/crontabs/helen"
printf '17 * * * * root backup-now\n' > "$B/etc/cron.d/sys"
chgrp "`awk -F: '$1 != "root" { print $1; exit }' /etc/group`" "$B/etc/cron.d/sys" 2>/dev/null || true
chmod 664 "$B/etc/cron.d/sys"
run "$B" "$W/out"
has '--FAIL-- [cron008f]' "$W/out" &&
has 'helen' "$W/out" &&
has '--WARN-- [cron001w]' "$W/out" &&
has 'backup-now' "$W/out" &&
has '--WARN-- [cron008w]' "$W/out" &&
  ok "writable tab, relative command, writable drop-in: all three" || { bad "bad"; cat "$W/out"; }

T=$W/tight
mkdir -p "$T/etc" "$T/var/spool/cron/crontabs" "$T/etc/cron.d"
printf '0 9 * * * /usr/local/bin/good\n' > "$T/var/spool/cron/crontabs/helen"
chmod 600 "$T/var/spool/cron/crontabs/helen"
printf '17 * * * * root /usr/bin/true\n' > "$T/etc/cron.d/sys"
chmod 644 "$T/etc/cron.d/sys"
run "$T" "$W/out"
if [ "`id -u`" -eq 0 ]; then
  empty "$W/out" &&
    ok "locked tabs, full pathnames: silent" || { bad "tight noisy"; cat "$W/out"; }
else
  # as a user the fixtures stay user-owned: the ownership judgment
  # reports them, which proves it works
  has '--WARN-- [cron009w]' "$W/out" &&
    ok "user-owned tabs: ownership reported" || { bad "tight blind"; cat "$W/out"; }
fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
