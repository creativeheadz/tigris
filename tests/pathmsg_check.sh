#!/bin/sh
#
# tests/pathmsg_check.sh - pathmsg gives each finding the letter of its level
#
# pathmsg (initdefs) is given an id for "not owned by" and one for
# "writable by", without their last letter, and decides the level from the
# file: it then adds the letter, so every id it reports names one level as
# the JSON schema requires. It reads lgetpermit lines (component, owner,
# group, then the nine permission bits and setuid, setgid, sticky); here
# they are written by hand for a real executable and a real directory.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/d"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

X=$W/x D=$W/d
: > "$X"; chmod 755 "$X"
echo "Tigris_JSON_File='$W/out.jsonl'" >> "$W/tigris.conf"
cat > "$W/drive.sh" <<EOF
basedir=\$TIGERHOMEDIR
. \$basedir/config
. \$BASEDIR/initdefs
#                  owner group  u: r w x  g: r w x  o: r w x  suid sgid sticky
echo "$X root root  1 1 1  1 0 1  1 1 1  0 0 0" | pathmsg tst001 tst002 "$X" root "World" ""
echo "$X root root  1 1 1  1 1 1  1 0 1  0 0 0" | pathmsg tst001 tst002 "$X" root "Group" ""
echo "$D root root  1 1 1  1 0 1  1 1 1  0 0 0" | pathmsg tst001 tst002 "$D" root "Dir" ""
echo "$X bin bin    1 1 1  1 0 1  1 0 1  0 0 0" | pathmsg tst001 tst002 "$X" root "Owner" ""
echo "$D bin bin    1 1 1  1 0 1  1 0 1  0 0 0" | pathmsg tst001 tst002 "$D" root "Dirowner" ""
echo "$X nobody nogroup  1 1 1  1 0 1  1 0 1  0 0 0" | pathmsg tst001 tst002 "$X" alice "User" ""
echo "$D root root  1 1 1  1 1 1  1 1 1  0 0 1" | pathmsg tst001 tst002 "$X" root "Sticky" ""
EOF
( cd "$W" && TIGERHOMEDIR=$W sh ./drive.sh ) > "$W/out" 2>&1
has() { grep -q "\"level\":\"$1\",\"id\":\"$2\",\"check\":\"drive.sh\",\"message\":\"$3 " "$W/out.jsonl"; }

has FAIL tst002f World  && ok "world-writable executable: FAIL, id ending in f" || bad "world"
has WARN tst002w Group  && ok "group-writable executable: WARN, w" || bad "group"
has INFO tst002i Dir    && ok "world-writable directory: INFO, i" || bad "directory"
has WARN tst001w Owner  && ok "executable not owned by root: WARN, w" || bad "owner"
has INFO tst001i Dirowner && ok "directory not owned by root: INFO, i" || bad "directory owner"
has WARN tst001w User   && ok "not owned by the user expected (owned by nobody): WARN, w" || bad "user"
[ "`grep -c '"id":"tst00[12]"' "$W/out.jsonl"`" = 0 ] && ok "no id without its letter" || bad "an id without its letter"
grep -q '"message":"Sticky ' "$W/out.jsonl" && bad "a sticky directory above the file was reported" || ok "a sticky world-writable directory above the file (/tmp) is not reported"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/out" "$W/out.jsonl"; }
exit $fail
