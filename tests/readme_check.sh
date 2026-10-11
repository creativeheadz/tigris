#!/bin/sh
#
# tests/readme_check.sh - the README's and ROADMAP's numbers are the tree's
#
# util/mkreadme -c: the finding ids, categories and test suites that the
# README's badges, text and category table give, and the numbers in the
# ROADMAP's comparison table, are what meta/, tests/ and version.h say.
# They were typed by hand once and drifted for a week. When this fails,
# run sh util/mkreadme and commit what it changes.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
out=`sh "$TIGER/util/mkreadme" -c "$TIGER" 2>&1`; st=$?
if [ $st -eq 0 ]; then
  echo "ok   README.md and ROADMAP.md give the tree's numbers"
  echo "PASS"
  exit 0
fi
printf '%s\n' "$out"
echo "FAIL the numbers have drifted (exit $st): run sh util/mkreadme"
exit 1
