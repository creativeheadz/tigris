#!/bin/sh
#
# tests/path_check.sh - check_path reads a PATH from users' files, runs none
#
# check_path finds the PATH a user's .profile or .cshrc sets and checks
# each directory in it. Those files are the users' own (an image's, under
# --root), so their assignments are read by path_value, never sourced
# (until October 2026 they were sourced, as root, after a filter that
# bash's expansions get past). Three users whose files use the usual
# forms: bob's .profile appends $HOME/bin to the inherited PATH, carol's
# .cshrc puts ~/bin first, dave's .profile quotes '$HOME/lit' so that it
# stays text. Each bin directory is world-writable, so a directory that is
# found is reported. Needs no root and touches nothing outside a
# temporary directory.
#
# Exit 0 when every assertion holds, 1 otherwise.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

H=$W/fx/home
mkdir -p "$H/bob/bin" "$H/carol/bin" "$H/dave/lit"
chmod 777 "$H/bob/bin" "$H/carol/bin" "$H/dave/lit"
printf 'export PATH=$PATH:$HOME/bin\n' > "$H/bob/.profile"
printf 'set path = ( ~/bin /usr/bin )\n' > "$H/carol/.cshrc"
printf "PATH='\$HOME/lit':/usr/bin\nexport PATH\n" > "$H/dave/.profile"
cat > "$W/fx/passwd" <<FX
bob:x:1002:1002:Bob:$H/bob:/bin/sh
carol:x:1003:1003:Carol:$H/carol:/bin/csh
dave:x:1004:1004:Dave:$H/dave:/bin/sh
FX
echo "the test's passwd file" > "$W/fx/passwd.src"
echo "$W/fx/passwd" > "$W/fx/pass.list"
cat >> "$W/tigris.conf" <<FX
Tigris_PasswdFiles='$W/fx/pass.list'
Tigris_Check_PATHALL=Y
FX

( cd "$W" && TIGERHOMEDIR=$W sh scripts/check_path ) 2>&1 |
  # one finding per line, its wrapped lines joined
  awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' > "$W/out"

grep -q "path01[12]w.*bob's .profile.*$H/bob/bin" "$W/out" &&
  ok "\$HOME in bob's .profile is his home" || bad "bob's \$HOME/bin not found"
grep -q "path005w.*bob" "$W/out" &&
  bad "path005w for bob: \$PATH read as empty, so '.' first" || ok "\$PATH is the inherited one, no '.' for bob"
grep -q "path01[12]w.*carol's .cshrc.*$H/carol/bin" "$W/out" &&
  ok "~ in carol's .cshrc is her home" || bad "carol's ~/bin not found"
grep -q "$H/dave/lit" "$W/out" &&
  bad "dave's quoted '\$HOME/lit' was expanded" || ok "single quotes keep \$HOME as text"

[ $fail -eq 0 ] || sed 's/^/     /' "$W/out"
[ $fail -eq 0 ] && echo "path_check: all assertions hold" || echo "path_check: FAILED"
exit $fail
