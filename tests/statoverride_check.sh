#!/bin/sh
#
# tests/statoverride_check.sh - deb_statoverride against a list of overrides
#
# Feeds the check a "dpkg-statoverride --list" of its own through
# Tigris_Deb_StatOverride_Cmd, for files this test creates, owned by whoever
# runs it: one that matches, one whose setgid bit is gone, one whose group
# is not the one set (written "#N"), one listed with a leading zero, one
# with a space in its name, and one that does not exist. Needs no root and
# no dpkg; tests/deb_checks.sh tries the real thing in a container.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/f"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

u=`id -un` g=`id -gn` gid=`id -g`
other=$((gid + 1))
for f in a b c d "e f"; do : > "$W/f/$f"; done
chmod 2755 "$W/f/a"; chmod 755 "$W/f/b" "$W/f/c"; chmod 640 "$W/f/d"; chmod 4750 "$W/f/e f"
cat > "$W/list" <<EOF
$u $g 2755 $W/f/a
$u $g 2755 $W/f/b
$u #$other 755 $W/f/c
$u $g 0640 $W/f/d
$u $g 4750 $W/f/e f
$u $g 4755 $W/f/missing
EOF

{
  echo "Tigris_Deb_StatOverride_Cmd='cat $W/list'"
  echo "Tigris_JSON_File='$W/out.jsonl'"
} >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/deb_statoverride ) > "$W/out" 2>&1
A="$W/out.jsonl"
has() { grep -F -q -- "$1" "$A"; }

has '"level":"WARN","id":"lin039w","check":"deb_statoverride","message":"`'"$W/f/b"''"'"' has a different mode or owner than dpkg-statoverride sets for it.","detail":"dpkg-statoverride sets '"$u:$g"' 2755; the file is '"$u:$g"' 755. To restore it: chown '"$u:$g"' '"'$W/f/b'"' && chmod 2755 '"'$W/f/b'"' (in that order: chown clears the setuid and setgid bits)."' &&
  ok "a setgid bit gone: lin039w, with what is set, what is found and the fix" || bad "b: `cat "$A"`"
has '`'"$W/f/c"''"'"' has a different mode or owner' && has "sets $u:#$other 755; the file is $u:$g 755. To restore it: chown $u:$other " &&
  ok "a group written #N that is not the file's; chown is given the number" || bad "c: `cat "$A"`"
[ "`grep -c lin039w "$A"`" = 2 ] &&
  ok "a match, a leading zero, a space in the name and a missing file are not reported" || bad "expected 2 findings: `cat "$A"`"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/out"; }
exit $fail
