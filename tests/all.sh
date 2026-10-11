#!/bin/sh
#
# tests/all.sh - every fixture suite, one line each
#
# Runs tests/*_check.sh and prints each one's last line (PASS, or why it
# skipped); exits 1 when one failed. A suite that cannot run here (no
# python for JSON, no GNU find for the offline scan) says SKIP or "nothing
# to test" and does not fail. CI runs this under mawk, gawk and busybox
# awk, in Debian, Arch and Alpine containers; deb_checks.sh and
# pkg_checks.sh change the system they run on and have jobs of their own.
# Check authors take note: busybox awk rejects a literal brace outside
# a bracket expression (/{/ does not compile, and the whole program
# dies silent), so every awk regex spells one [{] or [}].
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
export TIGER
# the tree copies the tests make carry this checkout's modes: a tigerrc
# or profile that group may write is (rightly) ignored, so make them 644
umask 022
fail=0
# which awk: gawk and mawk say with --version or -W version; busybox's says
# nothing, but awk is then a link to busybox
v=`awk --version 2>/dev/null | head -1`
[ -n "$v" ] || v=`awk -W version 2>/dev/null | head -1`
[ -n "$v" ] || v=`readlink -f "\`command -v awk\`" 2>/dev/null`
echo "awk: ${v:-unknown}"
for t in "$TIGER"/tests/*_check.sh
do
  name=${t##*/}
  case "$name" in schema_check.sh) continue ;; esac
  out=`sh "$t" < /dev/null 2>&1`
  last=`printf '%s\n' "$out" | tail -1`
  case "$last" in
    PASS|*"all assertions hold") printf 'ok    %s\n' "$name" ;;
    SKIP*|*"nothing to test"*) printf 'skip  %s: %s\n' "$name" "$last" ;;
    *) printf 'FAIL  %s\n' "$name"; printf '%s\n' "$out" | grep -v '^ok ' | head -15 | sed 's/^/      /'; fail=1 ;;
  esac
done
exit $fail
