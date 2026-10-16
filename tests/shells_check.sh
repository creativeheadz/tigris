#!/bin/sh
#
# tests/shells_check.sh - check_shells on offline roots
#
# Six roots: TMOUT in profile.d; autologout in csh.login; both,
# reported together; no timeout anywhere (a commented TMOUT does
# not count); TMOUT=0, which disables; and an empty root, where no
# startup files exist and nothing is said. INFO findings only show
# with Tiger_Show_INFO_Msgs=Y. Runs as a user and as root; the
# fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run() {  # run ROOT OUTFILE: check_shells with ROOT as the audited system
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./scripts/check_shells ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

T=$W/tmout; mkdir -p "$T/etc/profile.d"
printf '# system profile\numask 022\n' > "$T/etc/profile"
printf 'TMOUT=600\nreadonly TMOUT\nexport TMOUT\n' > "$T/etc/profile.d/timeout.sh"
run "$T" "$W/out"
has '--INFO-- [shl002i]' "$W/out" &&
has 'TMOUT=600 in /etc/profile.d/timeout.sh' "$W/out" &&
! grep -q 'shl001w' "$W/out" &&
  ok "TMOUT in profile.d: inventory with value" || { bad "tmout"; cat "$W/out"; }

C=$W/csh; mkdir -p "$C/etc"
printf '# system profile\numask 022\n' > "$C/etc/profile"
printf 'set autologout = 30\n' > "$C/etc/csh.login"
run "$C" "$W/out"
has 'autologout=30 in /etc/csh.login' "$W/out" &&
! grep -q 'shl001w' "$W/out" &&
  ok "autologout in csh.login: inventory" || { bad "csh"; cat "$W/out"; }

B=$W/both; mkdir -p "$B/etc/profile.d"
printf 'export TMOUT=900\n' > "$B/etc/profile"
printf 'set autologout=15\n' > "$B/etc/csh.login"
printf 'TMOUT=600\n' > "$B/etc/profile.d/timeout.sh"
run "$B" "$W/out"
has 'TMOUT=600 in /etc/profile.d/timeout.sh' "$W/out" &&
has 'TMOUT=900 in /etc/profile' "$W/out" &&
has 'autologout=15 in /etc/csh.login' "$W/out" &&
  ok "both families: all values reported" || { bad "both"; cat "$W/out"; }

N=$W/none; mkdir -p "$N/etc"
printf '# TMOUT=600 would go here\numask 022\n' > "$N/etc/profile"
run "$N" "$W/out"
has '--WARN-- [shl001w]' "$W/out" &&
! grep -q 'shl002i' "$W/out" &&
  ok "no timeout (commented one ignored): shl001w" || { bad "none"; cat "$W/out"; }

Z=$W/zero; mkdir -p "$Z/etc"
printf 'TMOUT=0\n' > "$Z/etc/profile"
run "$Z" "$W/out"
has '--WARN-- [shl001w]' "$W/out" &&
  ok "TMOUT=0 disables: shl001w" || { bad "zero"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no startup files: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
