#!/bin/sh
#
# tests/json_check.sh - the JSON Lines report
#
# 1. Calls message() directly with quotes, backslashes, tabs, control
#    characters and non-ASCII bytes and checks every line parses and
#    round-trips (non-ASCII bytes come back as \u00XX, one per byte).
# 2. Runs check_sysctl against the all-bad fixture with JSON on and checks
#    the JSON has one finding per text finding, with matching ids.
#
# Needs python3 for the parsing; skips with exit 2 without it.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
command -v python3 >/dev/null || { echo "SKIP: python3 needed to parse JSON"; exit 2; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0

# --- 1. the escaper, through message() itself
cat > "$W/emit.sh" <<'EOF'
TIGERHOMEDIR=$1
export TIGERHOMEDIR
out=$2
cd "$1" || exit 1
set --                      # config parses the command line; give it none
. ./config >/dev/null 2>&1
. ./initdefs
Tigris_JSON_File=$out
export Tigris_JSON_File
message WARN test001w "" 'quote " backslash \ tab	end'
message FAIL test002f 'second line' 'control char here'
message ALERT test003a "" 'latin1 file name: caf'$(printf '\351')' and utf8: caf'$(printf '\303\251')
message INFO test004i "" 'an info line'
EOF
sh "$W/emit.sh" "$W" "$W/out.jsonl" >/dev/null 2>&1
python3 - "$W/out.jsonl" <<'EOF' && echo "ok   escaper round-trips quotes, backslashes, tabs, control and non-ASCII bytes" || { echo "FAIL escaper"; fail=1; }
import json, sys
lines = [l for l in open(sys.argv[1], encoding='ascii').read().splitlines() if l]
recs = [json.loads(l) for l in lines]
assert [r["id"] for r in recs] == ["test001w", "test002f", "test003a", "test004i"], recs
assert recs[0]["message"] == 'quote " backslash \\ tab\tend', recs[0]
assert recs[1]["detail"] == "second line" and recs[1]["level"] == "FAIL"
m = recs[2]["message"].encode("latin-1")          # one \u00XX per byte
assert m == b"latin1 file name: caf\xe9 and utf8: caf\xc3\xa9", m
assert recs[3]["level"] == "INFO"                 # INFO is always in the JSON
assert all(r["type"] == "finding" and r["check"] == "emit.sh" for r in recs)
EOF
[ $fail -eq 0 ] || { echo "--- out.jsonl"; cat "$W/out.jsonl"; }

# --- 2. a real check: text and JSON agree
mkdir -p "$W/bad/proc/sys/kernel" "$W/bad/proc/sys/fs"
echo 0 > "$W/bad/proc/sys/kernel/kptr_restrict"
echo 0 > "$W/bad/proc/sys/kernel/randomize_va_space"
echo 0 > "$W/bad/proc/sys/fs/protected_symlinks"
{
  echo "Tigris_Sysctl_Root='$W/bad'"
  echo "Tigris_JSON_File='$W/sysctl.jsonl'"
} >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh systems/Linux/2/check_sysctl 2>&1 ) > "$W/sysctl.txt"
# CONFIG lines (codes ending in c) are echoed by config itself, not by message()
text_ids=`grep -oE '\[[a-z]+[0-9]{3}[a-bd-z]\]' "$W/sysctl.txt" | tr -d '[]' | sort | tr '\n' ' '`
json_ids=`python3 -c 'import json,sys; print(" ".join(sorted(json.loads(l)["id"] for l in open(sys.argv[1]) if l.strip())), end=" ")' "$W/sysctl.jsonl"`
if [ "$text_ids" = "$json_ids" ] && [ -n "$text_ids" ]; then
  echo "ok   check_sysctl: JSON findings match the text findings ($text_ids)"
else
  echo "FAIL ids differ: text [$text_ids] json [$json_ids]"; fail=1
fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
