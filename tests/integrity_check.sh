#!/bin/sh
#
# tests/integrity_check.sh - check_integrity on offline roots
#
# Roots: AIDE configured with no database, with its database built,
# and with an empty one; Fedora's database_in through @@define, with
# nothing built, with only database_out built, and in place; macros
# that cannot be known offline, and @@ifdef followed; Debian's
# database_in, and one set in aide.conf.d through @@x_include; AFICK
# with no database (its name takes extensions); Samhain and osquery
# present; and an empty root, where no watcher is configured and
# nothing is said. INFO
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
has '--WARN-- [int001w] AIDE is configured (/etc/aide/aide.conf) but its database (/var/lib/aide/aide.db) was never built' "$W/out" &&
has '--INFO-- [int003i] AIDE is the file-integrity watcher in place.' "$W/out" &&
  ok "AIDE with no database: int001w plus inventory" || { bad "blind"; cat "$W/out"; }

A=$W/aideok; mkdir -p "$A/etc/aide" "$A/var/lib/aide"
printf 'database=file:/var/lib/aide/aide.db\n' > "$A/etc/aide/aide.conf"
printf 'db-bytes' > "$A/var/lib/aide/aide.db"
run "$A" "$W/out"
has '--INFO-- [int003i] AIDE is the file-integrity watcher in place.' "$W/out" &&
! grep -q 'int001w' "$W/out" &&
  ok "AIDE with its database: only inventory" || { bad "aideok"; cat "$W/out"; }

: > "$A/var/lib/aide/aide.db"
run "$A" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide/aide.conf) but its database (/var/lib/aide/aide.db) was never built' "$W/out" &&
  ok "AIDE with an empty database: int001w" || { bad "aide empty db"; cat "$W/out"; }

# Fedora's shape: database_in and database_out through @@define DBDIR
R=$W/fedora; mkdir -p "$R/etc" "$R/var/lib/aide"
printf '@@define DBDIR /var/lib/aide\n@@define LOGDIR /var/log/aide\ndatabase_in=file:@@{DBDIR}/aide.db.gz\n#database_out=file:aide.db.new\ndatabase_out=file:@@{DBDIR}/aide.db.new.gz\ngzip_dbout=yes\n' > "$R/etc/aide.conf"
run "$R" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide.conf) but its database (/var/lib/aide/aide.db.gz) was never built' "$W/out" &&
  ok "database_in through @@{DBDIR}, nothing built: int001w names it" || { bad "fedora"; cat "$W/out"; }
printf 'db-bytes' > "$R/var/lib/aide/aide.db.new.gz"
run "$R" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide.conf) but its database (/var/lib/aide/aide.db.gz) is not in place' "$W/out" &&
has "'aide --init' wrote /var/lib/aide/aide.db.new.gz; move it to /var/lib/aide/aide.db.gz." "$W/out" &&
  ok "database_out built but never moved: int001w says where it is" || { bad "fedora new"; cat "$W/out"; }
printf 'db-bytes' > "$R/var/lib/aide/aide.db.gz"
run "$R" "$W/out"
! grep -q 'int001w' "$W/out" &&
  ok "database_in through @@{DBDIR}, in place: nothing" || { bad "fedora ok"; cat "$W/out"; }

# a macro nobody defines, or one set under a condition only AIDE can
# decide: not judged
U=$W/unknown; mkdir -p "$U/etc"
printf 'database_in=file:@@{NOWHERE}/aide.db\n' > "$U/etc/aide.conf"
run "$U" "$W/out"
! grep -q 'int001w' "$W/out" && has 'int003i' "$W/out" &&
  ok "an undefined macro: not judged" || { bad "undefined macro"; cat "$W/out"; }
printf '@@ifhost backup\n@@define DBDIR /srv/aide\n@@endif\ndatabase_in=file:@@{DBDIR}/aide.db\n' > "$U/etc/aide.conf"
run "$U" "$W/out"
! grep -q 'int001w' "$W/out" &&
  ok "a macro set under @@ifhost: not judged" || { bad "ifhost macro"; cat "$W/out"; }
# @@ifdef followed: only the branch taken names the database
printf '@@define DBDIR /var/lib/aide\n@@ifdef DBDIR\ndatabase_in=file:@@{DBDIR}/taken.db\n@@else\ndatabase_in=file:/var/lib/aide/other.db\n@@endif\n' > "$U/etc/aide.conf"
mkdir -p "$U/var/lib/aide"; printf 'db-bytes' > "$U/var/lib/aide/other.db"
run "$U" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide.conf) but its database (/var/lib/aide/taken.db) was never built' "$W/out" &&
  ok "@@ifdef: the branch taken names the database" || { bad "ifdef"; cat "$W/out"; }

# Debian's shape: database_in in aide.conf, the rules from aide.conf.d
# through @@x_include with a regular expression; a file whose name does
# not match and a program AIDE would run say nothing
D=$W/debian; mkdir -p "$D/etc/aide/aide.conf.d" "$D/var/lib/aide"
printf '@@x_include_setenv UPAC_settingsd /etc/aide/aide.settings.d\ndatabase_in=file:/var/lib/aide/aide.db\ndatabase_out=file:/var/lib/aide/aide.db.new\n@@x_include /etc/aide/aide.conf.d ^[a-zA-Z0-9_-]+$\n' > "$D/etc/aide/aide.conf"
printf '/var/log/apt Log\n' > "$D/etc/aide/aide.conf.d/31_aide_apt"
run "$D" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide/aide.conf) but its database (/var/lib/aide/aide.db) was never built' "$W/out" &&
  ok "database_in= (aide-common): int001w" || { bad "debian"; cat "$W/out"; }
printf 'db-bytes' > "$D/var/lib/aide/aide.db"
run "$D" "$W/out"
! grep -q 'int001w' "$W/out" &&
  ok "database_in= with its database: nothing" || { bad "debian ok"; cat "$W/out"; }
printf '@@x_include /etc/aide/aide.conf.d ^[a-zA-Z0-9_-]+$\n' > "$D/etc/aide/aide.conf"
printf 'database_in=file:/srv/aide/aide.db\n' > "$D/etc/aide/aide.conf.d/10_aide_db"
printf 'database_in=file:/var/lib/aide/aide.db\n' > "$D/etc/aide/aide.conf.d/10_aide_db.dpkg-old"
printf '#!/bin/sh\necho database_in=file:/var/lib/aide/aide.db\ndatabase_in=file:/var/lib/aide/aide.db\n' > "$D/etc/aide/aide.conf.d/20_aide_script"
chmod 755 "$D/etc/aide/aide.conf.d/20_aide_script"
# and a file that includes its own directory again: each file is read once
printf '@@x_include /etc/aide/aide.conf.d ^[a-zA-Z0-9_-]+$\n' > "$D/etc/aide/aide.conf.d/30_aide_loop"
run "$D" "$W/out"
has '--WARN-- [int001w] AIDE is configured (/etc/aide/aide.conf) but its database (/srv/aide/aide.db) was never built' "$W/out" &&
  ok "database_in from aide.conf.d; unmatched names, programs and loops not read" || { bad "debian conf.d"; cat "$W/out"; }
grep -q "$D" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

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
