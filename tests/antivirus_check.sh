#!/bin/sh
#
# tests/antivirus_check.sh - check_antivirus on offline roots
#
# Five roots: ClamAV with fresh signatures; signatures older than a
# week; a freshclam.conf but no databases at all; a DatabaseDirectory
# elsewhere, read from the config; and an empty root, where no
# scanner is installed and nothing is said. INFO findings only show
# with Tigris_Show_INFO_Msgs=Y. Runs as a user and as root; the
# fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_antivirus with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_antivirus ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

F=$W/fresh; mkdir -p "$F/etc" "$F/usr/bin" "$F/var/lib/clamav"
printf '#!/bin/sh\n' > "$F/usr/bin/clamscan"
chmod 755 "$F/usr/bin/clamscan"
printf 'clamav\n' > "$F/var/lib/clamav/daily.cld"
run "$F" "$W/out"
has '--INFO-- [avir002i]' "$W/out" &&
has 'fresh signatures in /var/lib/clamav' "$W/out" &&
! grep -q 'avir001w' "$W/out" &&
  ok "fresh signatures: inventory only" || { bad "fresh"; cat "$W/out"; }

S=$W/stale; mkdir -p "$S/etc" "$S/usr/bin" "$S/var/lib/clamav"
printf '#!/bin/sh\n' > "$S/usr/bin/clamscan"
chmod 755 "$S/usr/bin/clamscan"
printf 'clamav\n' > "$S/var/lib/clamav/daily.cvd"
touch -t 202001010000 "$S/var/lib/clamav/daily.cvd"
run "$S" "$W/out"
has '--WARN-- [avir001w]' "$W/out" &&
has 'older than a week' "$W/out" &&
! grep -q 'avir002i' "$W/out" &&
  ok "week-old signatures: avir001w" || { bad "stale"; cat "$W/out"; }

M=$W/missing; mkdir -p "$M/etc/clamav" "$M/var/lib/clamav"
printf 'DatabaseDirectory /var/lib/clamav\n' > "$M/etc/clamav/freshclam.conf"
run "$M" "$W/out"
has '--WARN-- [avir001w]' "$W/out" &&
has 'has no signatures in /var/lib/clamav' "$W/out" &&
  ok "configured but never fetched: avir001w" || { bad "missing"; cat "$W/out"; }

C=$W/custom; mkdir -p "$C/etc/clamav" "$C/srv/av"
printf '# local mirrors land here\nDatabaseDirectory /srv/av  # moved off root\n' > "$C/etc/clamav/freshclam.conf"
printf 'clamav\n' > "$C/srv/av/daily.cld"
run "$C" "$W/out"
has '--INFO-- [avir002i]' "$W/out" &&
has 'fresh signatures in /srv/av' "$W/out" &&
! grep -q 'avir001w' "$W/out" &&
  ok "DatabaseDirectory elsewhere: read from the config" || { bad "custom"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no scanner installed: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
