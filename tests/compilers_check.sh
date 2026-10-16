#!/bin/sh
#
# tests/compilers_check.sh - check_compilers on offline roots
#
# Four roots: a toolchain with a scanner beside it; a world-writable
# gcc; a gcc writable by its group, which is not root's; and an empty
# root, where neither is installed and nothing is said. INFO findings
# only show with Tiger_Show_INFO_Msgs=Y. Runs as a user and as root;
# the fixtures read the same for both.
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
run() {  # run ROOT OUTFILE: check_compilers with ROOT as the audited system
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_compilers ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$2" || true
}
has() { grep -F -q -- "$1" "$2"; }

T=$W/toolchain; mkdir -p "$T/etc" "$T/usr/bin"
printf '#!/bin/sh\n' > "$T/usr/bin/gcc"; printf '#!/bin/sh\n' > "$T/usr/bin/cc"
printf '#!/bin/sh\n' > "$T/usr/bin/rkhunter"
chmod 755 "$T/usr/bin/gcc" "$T/usr/bin/cc" "$T/usr/bin/rkhunter"
run "$T" "$W/out"
has '--INFO-- [cmp001i] C compilers are installed (/usr/bin/cc /usr/bin/gcc)' "$W/out" &&
has '--INFO-- [cmp003i]' "$W/out" && has 'rkhunter scans this box' "$W/out" &&
! grep -q 'cmp002w' "$W/out" &&
  ok "a toolchain with a scanner: inventory only" || { bad "toolchain"; cat "$W/out"; }

O=$W/world; mkdir -p "$O/etc" "$O/usr/bin"
printf '#!/bin/sh\n' > "$O/usr/bin/gcc"
chmod 757 "$O/usr/bin/gcc"
run "$O" "$W/out"
has "--WARN-- [cmp002w] The compiler \`/usr/bin/gcc' is writable past root" "$W/out" &&
  ok "a world-writable gcc: cmp002w" || { bad "world"; cat "$W/out"; }

G=$W/group; mkdir -p "$G/etc" "$G/usr/bin"
printf '#!/bin/sh\n' > "$G/usr/bin/gcc"
chgrp "`id -gn`" "$G/usr/bin/gcc"
chmod 775 "$G/usr/bin/gcc"
run "$G" "$W/out"
if [ "`id -gn`" = root ]; then
  ! grep -q 'cmp002w' "$W/out" &&
    ok "root's group writing changes nothing: no cmp002w" || { bad "group-root"; cat "$W/out"; }
else
  has '--WARN-- [cmp002w]' "$W/out" &&
    ok "a gcc writable by a non-root group: cmp002w" || { bad "group"; cat "$W/out"; }
fi

E=$W/empty; mkdir -p "$E/etc"
run "$E" "$W/out"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } ||
  ok "no compilers and no scanners: nothing said"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
