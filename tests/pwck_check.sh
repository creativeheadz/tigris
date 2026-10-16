#!/bin/sh
#
# tests/pwck_check.sh - what check_passwd makes of pwck's output (pass006w)
#
# pwck -r says "directory ... does not exist" of every account whose home
# is missing; on every stock Debian and Ubuntu host that is lp, news,
# uucp, www-data, list and irc, whose shell is nologin. Those lines are
# no fault and must not make pass006w; the same line about an account
# that logs in must. A stand-in for pwck prints both, about an account of
# this host's /etc/passwd with a nologin or false shell and about root.
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

nologin=`awk -F: '$7 ~ /\/(nologin|false)$/ { print $1; exit }' /etc/passwd`
rootsh=`awk -F: '$1 == "root" { print $7 }' /etc/passwd`
if [ -z "$nologin" ] || [ "$(uname -s)" != Linux ]; then
  echo "ok   (no nologin account here, or not Linux: nothing to test)"; echo PASS; exit 0
fi
case "$rootsh" in */nologin|*/false|'') echo "ok   (root does not log in here: nothing to test)"; echo PASS; exit 0 ;; esac

cat > "$W/drive.sh" <<'EOF'
basedir=$TIGERHOMEDIR
. $basedir/config
PWCK="sh $STUB" Tigris_Output_Width=0
export PWCK Tigris_Output_Width
sh $BASEDIR/scripts/check_passwd
EOF
go() {  # go LINE...: pwck prints the lines
  { echo '#!/bin/sh'; for l; do printf "echo \"%s\"\n" "$l"; done; echo 'echo "pwck: no changes"'; echo 'exit 2'; } > "$W/pwck"
  ( cd "$W" && TIGERHOMEDIR=$W STUB="$W/pwck" sh ./drive.sh ) > "$W/out" 2>&1
}

go "user '$nologin': directory '/zz-gone/$nologin' does not exist" "user 'root': directory '/zz-gone/root' does not exist"
grep -q '\[pass006w\] Integrity of password files questionable' "$W/out" &&
  grep -q "user 'root': directory '/zz-gone/root' does not exist" "$W/out" &&
  ok "a missing home of an account that logs in (root): pass006w" || { bad "root's missing home"; cat "$W/out"; }
grep -q "zz-gone/$nologin" "$W/out" &&
  bad "a missing home of $nologin, whose shell is nologin, was reported" || ok "the same of $nologin, whose shell is nologin or false: not"
grep -q 'pwck: no changes' "$W/out" && bad "pwck's 'no changes' was part of the finding" || ok "pwck's 'no changes' is not part of it"

go "user '$nologin': directory '/zz-gone/$nologin' does not exist"
grep -q 'pass006w' "$W/out" &&
  { bad "nothing but no-login accounts' homes made pass006w"; cat "$W/out"; } || ok "only no-login accounts' homes missing: no pass006w"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
