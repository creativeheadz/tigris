#!/bin/sh
#
# tests/private_check.sh - nothing in the tree names the maintainer's own
# machine, network or account
#
# The repository is public. Fixtures and documentation once carried the
# maintainer's desktop's name, its LAN address, a home path and a user
# name, which is nobody's business and a small gift to anyone looking at
# that network. Every file but the history (CHANGES, debian/) and this
# test is searched for them; a hit fails. The maintainer's address in the
# packaging and SECURITY.md is the contact, and stays.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022
fail=0
hits=`cd "$TIGER" && find . -type f ! -path './.git/*' ! -path './log/*' ! -path './run/*' ! -path './debian/*' ! -name CHANGES ! -name private_check.sh ! -name explanations.html -print0 2>/dev/null |
  xargs -0 grep -anE '192\.168\.1\.[0-9]|/home/andrei|/media/andrei|[^a-zA-Z]Hera[^a-zA-Z]|[^a-zA-Z.]andrei[^a-zA-Z@.]' 2>/dev/null | head -20`
if [ -z "$hits" ]; then
  echo "ok   no file names the maintainer's machine, network, home or account"
else
  echo "FAIL these do:"; printf '%s\n' "$hits" | cut -c1-120 | sed 's/^/     /'; fail=1
fi
[ $fail -eq 0 ] && echo PASS || echo FAIL
exit $fail
