#!/bin/sh
#
# tests/integrity_check.sh - check_integrity on offline roots
#
# Five roots: AIDE configured with no database; AIDE with its
# database built; AFICK with no database (its name takes
# extensions); Samhain and osquery present; and an empty root,
# where no watcher is configured and nothing is said. INFO
# findings only show with Tigris_Show_INFO_Msgs=Y. Runs as a user
# and as root; the fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_integrity with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_integrity ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

B=$W/blind; mkdir -p "$B/etc/aide"
printf 'database=file:/var/lib/aide/aide.db\n' > "$B/etc/aide/aide.conf"
run "$B" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide/aide.conf) but its database was never built' "$W/out" &&
has '--INFO-- [int003i] AIDE is the file-integrity watcher in place.' "$W/out" &&
  ok "AIDE with no database: int001w plus inventory" || { bad "blind"; cat "$W/out"; }

A=$W/aideok; mkdir -p "$A/etc/aide" "$A/var/lib/aide"
printf 'database=file:/var/lib/aide/aide.db\n' > "$A/etc/aide/aide.conf"
printf 'db-bytes' > "$A/var/lib/aide/aide.db"
run "$A" "$W/out"
has '--INFO-- [int003i] AIDE is the file-integrity watcher in place.' "$W/out" &&
! grep -q 'int001w' "$W/out" &&
  ok "AIDE with its database: only inventory" || { bad "aideok"; cat "$W/out"; }

F=$W/afick; mkdir -p "$F/etc/afick" "$F/var/lib/afick"
printf 'database := /var/lib/afick/afick\n' > "$F/etc/afick/linux.conf"
run "$F" "$W/out"
has '--WARN-- [int002w] AFICK is configured (/etc/afick/linux.conf) but its database was never built' "$W/out" &&
  ok "AFICK with no database, via a drop-in: int002w" || { bad "afick"; cat "$W/out"; }
printf 'db-bytes' > "$F/var/lib/afick/afick.dbm.dir"
run "$F" "$W/out"
! grep -q 'int002w' "$W/out" &&
  ok "AFICK with an extended database name: nothing" || { bad "afick db"; cat "$W/out"; }

S=$W/other; mkdir -p "$S/etc/samhain" "$S/etc/osquery"
printf 'file = 0:/sbin\n' > "$S/etc/samhain/samhainrc"
printf '{}\n' > "$S/etc/osquery/osquery.conf"
run "$S" "$W/out"
has '--INFO-- [int003i] Samhain is the file-integrity watcher in place.' "$W/out" &&
has '--INFO-- [int003i] osquery is the file-integrity watcher in place.' "$W/out" &&
! grep -q 'int001w\|int002w' "$W/out" &&
  ok "Samhain and osquery: inventory only" || { bad "other"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no watcher configured: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
