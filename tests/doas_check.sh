#!/bin/sh
#
# tests/doas_check.sh - check_doas on offline roots
#
# Four roots: loose (an unrestricted nopass-as-root rule, a scoped
# nopass rule, and a group-writable doas.conf); tight (passworded
# rules only, root-owned 444); no doas.conf at all, where there is
# nothing to say; and a root-only rule, which grants root nothing
# new. Runs as a user and as root; the fixtures read the same for
# both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
echo "Tiger_Show_INFO_Msgs='Y'" >> "$W/tigerrc"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_doas with ROOT as the audited system
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/MacOSX/default/check_doas ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }
empty() { [ ! -s "$1" ]; }

B=$W/bad; mkdir -p "$B/etc"
cat > "$B/etc/doas.conf" <<'EOF'
# the helpdesk gets root without a password
permit nopass helpdesk as root
# backups may run their own script without a password
permit nopass backup as root cmd /usr/local/bin/backup args
# operators authenticate as usual
permit :operators as root
EOF
chgrp "`awk -F: '$1 != "root" { print $1; exit }' /etc/group`" "$B/etc/doas.conf" 2>/dev/null || true
chmod 664 "$B/etc/doas.conf"
run "$B" "$W/out"
has '--WARN-- [dos001w]' "$W/out" &&
has 'helpdesk' "$W/out" &&
has '--INFO-- [dos002i]' "$W/out" &&
has '--WARN-- [dos003w]' "$W/out" &&
  ok "nopass root, scoped nopass, writable conf: all three" || { bad "bad"; cat "$W/out"; }

T=$W/tight; mkdir -p "$T/etc"
cat > "$T/etc/doas.conf" <<'EOF'
permit persist :operators as root
EOF
chmod 444 "$T/etc/doas.conf"
run "$T" "$W/out"
empty "$W/out" &&
  ok "passworded rules, locked conf: silent" || { bad "tight noisy"; cat "$W/out"; }

E=$W/emptyroot; mkdir -p "$E/etc"
run "$E" "$W/out"
empty "$W/out" &&
  ok "no doas.conf: silent" || { bad "empty noisy"; cat "$W/out"; }

O=$W/rootrule; mkdir -p "$O/etc"
cat > "$O/etc/doas.conf" <<'EOF'
permit nopass root as root
EOF
chmod 444 "$O/etc/doas.conf"
run "$O" "$W/out"
empty "$W/out" &&
  ok "root-only nopass: silent" || { bad "rootrule noisy"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
