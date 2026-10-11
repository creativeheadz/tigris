#!/bin/sh
#
# tests/realpath_check.sh - symbolic links are resolved by util/realpath,
# whatever their length
#
# The symlink scan (on by default) lists every link on the host and hands
# the list to $REALPATH, so a link is a path any user chooses. Until
# October 2026 that was a C helper with fixed buffers, which a path or a
# target longer than them overran, in a root process. util/realpath is
# the resolver now, always: this feeds it a normal link, a 5000-byte
# line and a link whose target is as long as the kernel allows, in
# list mode and as arguments, and expects the normal one resolved, the
# others skipped, the exit status 0, and the Linux config to name
# util/realpath even when a bin/realpath is present. Needs no root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run --exclude=./bin -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/fx"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

: > "$W/fx/target"
ln -s "$W/fx/target" "$W/fx/link"
long=`awk 'BEGIN { s = "/"; while (length(s) < 5000) s = s "a"; print s }'`
# a target of 4095 bytes, the most a link may hold
ln -s "`awk 'BEGIN { s = "/t"; while (length(s) < 4095) s = s "b"; print s }'`" "$W/fx/longtarget"

# list mode, as check_links uses it
printf '%s\n%s\n%s\n' "$W/fx/link" "$long" "$W/fx/longtarget" | sh "$W/util/realpath" > "$W/out" 2>"$W/err"
st=$?
[ "$st" = 0 ] && ok "list mode exits 0 with a 5000-byte line in it" || bad "list mode exit $st: `head -2 "$W/err"`"
grep -qF "$W/fx/link $W/fx/target" "$W/out" && ok "the normal link is resolved" || { bad "the normal link is missing"; cat "$W/out"; }
[ "`wc -l < "$W/out"`" -le 3 ] && ok "nothing else was invented" || bad "`wc -l < "$W/out"` lines"

# argument mode with -d, as check_aliases and check_crontabs use it
r=`sh "$W/util/realpath" -d "$long" "$W/fx/link" 2>/dev/null`
st=$?
[ "$st" = 0 ] && ok "argument mode exits 0" || bad "argument mode exit $st"
printf '%s\n' "$r" | grep -qF "$W/fx/target" && ok "-d resolves the normal link" || { bad "-d: $r"; }

# the Linux config does not pick a bin/realpath up
mkdir -p "$W/bin"; printf '#!/bin/sh\necho picked-up\n' > "$W/bin/realpath"; chmod 755 "$W/bin/realpath"
r=`cd "$W" && TIGERHOMEDIR=$W sh -c '. ./config >/dev/null 2>&1; printf %s "$REALPATH"'`
case "$r" in
  */util/realpath) ok "REALPATH is util/realpath with a bin/realpath present" ;;
  *) bad "REALPATH is '$r'" ;;
esac

[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
