#!/bin/sh
#
# tests/execbit_check.sh - every script the dispatch runs is executable
#
# tiger and the systems/*/check dispatchers run checks directly
# ($SYSTEMDIR/check_foo, not sh check_foo), so a check committed
# without the execute bit dies with "Permission denied" on every
# source run — while the suites, which run sh check_foo, stay green.
# (systems/Linux/2/check_inetd shipped exactly that way, and the
# fleet caught it.) Every shebang'd file under systems/, scripts/
# and util/, plus the top-level tools, must be executable.
# systems/Linux/0 and systems/Linux/1 are unreachable since kernel 2
# (see tests/explain_check.sh) and grandfathered. Modes are read from
# a tree copy made under umask 022, so the verdict does not depend on
# the checkout's umask.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copy carries the index modes, not the cloner's
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# the tools beside the tree (tigris links to tiger, as the old explain name links to tigris-explain)
dark=
for t in tiger tigercron tigris-diff tigris-accept tigris-explain tigris-export
do
  [ -x "$W/$t" ] || dark="$dark $t"
done
[ -z "$dark" ] && ok "the top-level tools are executable" || bad "not executable:$dark"

# every shebang'd file under systems/, scripts/ and util/, except the
# unreachable Linux/0 and Linux/1
dark=`cd "$W" && grep -rl '^#!' systems scripts util 2>/dev/null |
  grep -v '^systems/Linux/[01]/' |
  while read -r f; do [ -x "$W/$f" ] || printf '%s\n' "$f"; done`
[ -z "$dark" ] && ok "every shebang'd systems, scripts and util file is executable" ||
  bad "not executable: `printf '%s' "$dark" | tr '\n' ' '`"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
