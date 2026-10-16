#!/bin/sh
#
# tests/accept_check.sh - accepted findings
#
# Uses tigris-accept to accept one finding outright, one with an expiry
# in the past and one with a message pattern that does not match, then
# runs check_sysctl against the all-bad fixture with JSON on. Checks that
# only the live acceptance leaves the text report, that the JSON keeps it
# marked accepted with the reason, and that list and delete work.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/bad/proc/sys/kernel" "$W/bad/proc/sys/fs"
echo 0 > "$W/bad/proc/sys/kernel/kptr_restrict"       # lin020w
echo 0 > "$W/bad/proc/sys/kernel/randomize_va_space"  # lin023f
echo 0 > "$W/bad/proc/sys/fs/protected_symlinks"      # lin029f
echo 0 > "$W/bad/proc/sys/kernel/dmesg_restrict"      # lin021w
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
A="$W/tigris-accept"

( cd "$W" && sh "$A" lin020w -r "kernel pointers are fine on this lab box" -u 2099-01-01 ) >/dev/null && ok "accept with reason and future expiry" || bad "accept"
( cd "$W" && sh "$A" lin023f -r "expired long ago" -u 2020-01-01 ) >/dev/null || bad "accept expired"
( cd "$W" && sh "$A" lin029f -m "fs.protected_symlinks is 7*" -r "pattern that will not match" ) >/dev/null || bad "accept with pattern"
( cd "$W" && sh "$A" lin021w ) >/dev/null 2>&1 && bad "accept without a reason was allowed" || ok "a reason is required"
( cd "$W" && sh "$A" lin021w -r x -u 1/2/2026 ) >/dev/null 2>&1 && bad "bad date accepted" || ok "the date must be YYYY-MM-DD"
[ `grep -vc '^#' "$W/tigris.accepted"` -eq 3 ] && ok "three entries in tigris.accepted" || bad "entries: `cat "$W/tigris.accepted"`"

{
  echo "Tigris_Sysctl_Root='$W/bad'"
  echo "Tigris_JSON_File='$W/out.jsonl'"
  echo "Tigris_Accepted_Log='$W/accepted.log'"
} >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh systems/Linux/2/check_sysctl 2>&1 ) > "$W/out.txt"

grep -q 'lin020w' "$W/out.txt" && bad "accepted lin020w still in the text" || ok "accepted finding left out of the text"
grep -q 'lin023f' "$W/out.txt" && ok "expired acceptance: finding reported again" || bad "expired acceptance still hides lin023f"
grep -q 'lin029f' "$W/out.txt" && ok "pattern that does not match: finding reported" || bad "pattern wrongly matched"
grep -q 'lin021w' "$W/out.txt" && ok "unaccepted finding reported" || bad "lin021w missing"
[ "`cat "$W/accepted.log" 2>/dev/null`" = "lin020w" ] && ok "the run counted one accepted finding" || bad "accepted log: `cat "$W/accepted.log" 2>/dev/null`"

if command -v python3 >/dev/null; then
python3 - "$W/out.jsonl" <<'EOF' && ok "JSON keeps the accepted finding, marked, with reason and date" || bad "JSON accepted marking"
import json, sys
recs = {}
for l in open(sys.argv[1]):
    if l.strip():
        r = json.loads(l); recs[r["id"]] = r
a = recs["lin020w"]["accepted"]
assert a["reason"] == "kernel pointers are fine on this lab box" and a["until"] == "2099-01-01", a
assert "accepted" not in recs["lin023f"] and "accepted" not in recs["lin029f"] and "accepted" not in recs["lin021w"]
EOF
fi

( cd "$W" && sh "$A" -l ) > "$W/list.txt"
grep -q 'lin023f.*(expired)' "$W/list.txt" && grep -q 'lab box' "$W/list.txt" && ok "list shows entries and marks the expired one" || bad "list: `cat "$W/list.txt"`"
( cd "$W" && sh "$A" -d lin020w ) >/dev/null && [ `grep -vc '^#' "$W/tigris.accepted"` -eq 2 ] && ok "delete removes an entry" || bad "delete"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out.txt"; cat "$W/out.txt"; }
exit $fail
