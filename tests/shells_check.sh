#!/bin/sh
#
# tests/shells_check.sh - check_shells on offline roots
#
# Nine roots: TMOUT in profile.d; autologout in csh.login; both,
# reported together; no timeout anywhere (a commented TMOUT does
# not count), which is information, not a warning; TMOUT=0, which
# disables; quoted values, which count; profile.d names with a
# blank and with a backslash, each one file reported as named; and
# an empty root, where no startup files exist and nothing is said. INFO findings only show
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
run() {  # run ROOT OUTFILE: check_shells with ROOT as the audited system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
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
! grep -q 'shl001' "$W/out" &&
  ok "TMOUT in profile.d: inventory with value" || { bad "tmout"; cat "$W/out"; }

C=$W/csh; mkdir -p "$C/etc"
printf '# system profile\numask 022\n' > "$C/etc/profile"
printf 'set autologout = 30\n' > "$C/etc/csh.login"
run "$C" "$W/out"
has 'autologout=30 in /etc/csh.login' "$W/out" &&
! grep -q 'shl001' "$W/out" &&
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
has '--INFO-- [shl001i]' "$W/out" &&
! grep -q 'shl002i\|WARN' "$W/out" &&
  ok "no timeout (commented one ignored): shl001i, information only" || { bad "none"; cat "$W/out"; }

Z=$W/zero; mkdir -p "$Z/etc"
printf 'TMOUT=0\n' > "$Z/etc/profile"
run "$Z" "$W/out"
has '--INFO-- [shl001i]' "$W/out" &&
  ok "TMOUT=0 disables: shl001i" || { bad "zero"; cat "$W/out"; }

Q=$W/quoted; mkdir -p "$Q/etc/profile.d"
printf 'umask 022\n' > "$Q/etc/profile"
printf 'TMOUT="900"\nreadonly TMOUT\nexport TMOUT\n' > "$Q/etc/profile.d/tmout.sh"
printf "set autologout='20'\n" > "$Q/etc/csh.login"
run "$Q" "$W/out"
has 'TMOUT=900 in /etc/profile.d/tmout.sh' "$W/out" &&
has 'autologout=20 in /etc/csh.login' "$W/out" &&
! grep -q 'shl001' "$W/out" &&
  ok "quoted values count" || { bad "quoted"; cat "$W/out"; }

# A name with a blank is one file, not two words (the second of
# which, timeout.sh, would be read from the root's / instead); a
# backslash in a name is shown as it is, not read as an escape
S=$W/names; mkdir -p "$S/etc/profile.d"
printf 'umask 022\n' > "$S/etc/profile"
printf 'TMOUT=600\n' > "$S/etc/profile.d/my timeout.sh"
printf 'TMOUT=777\n' > "$S/timeout.sh"
printf 'TMOUT=300\n' > "$S/etc/profile.d/x\\101.sh"
run "$S" "$W/out"
has 'TMOUT=600 in /etc/profile.d/my timeout.sh' "$W/out" &&
has 'TMOUT=300 in /etc/profile.d/x\101.sh' "$W/out" &&
! grep -q '777\|xA\.sh' "$W/out" &&
  ok "names with a blank or a backslash: one file each, named as they are" || { bad "names"; cat "$W/out"; }

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no startup files: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
