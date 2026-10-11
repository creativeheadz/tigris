#!/bin/sh
#
# tests/summary_check.sh - the transparent summary, from a JSON Lines report
#
# 1. util/summary on a synthetic report: the text (counts, distinct ids,
#    by category, the score with its formula) and -j (the distinct,
#    categories and score fields a summary record carries after its
#    counts, parsed with python3 when available).
# 2. A real tigris run with planted findings (as in exit_check.sh): the
#    text report ends with the summary, and its JSON summary record
#    carries the new fields; with the JSON report off there is no summary.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
S=$TIGER/util/summary
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

cat > "$W/r.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"r1","tool":"tigris","version":"3.5.0","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-07T10:00:00Z"}
{"type":"finding","level":"ALERT","id":"lin001a","check":"c1","message":"first","category":"network"}
{"type":"finding","level":"ALERT","id":"lin001a","check":"c1","message":"second"}
{"type":"finding","level":"FAIL","id":"lin002f","check":"c2","message":"f","category":"ssh"}
{"type":"finding","level":"WARN","id":"ssh003w","check":"c3","message":"w1","category":"ssh"}
{"type":"finding","level":"WARN","id":"ssh003w","check":"c3","message":"w2","category":"ssh"}
{"type":"finding","level":"WARN","id":"ssh004w","check":"c3","message":"w3","category":"ssh"}
{"type":"finding","level":"WARN","id":"acc005w","check":"c4","message":"acc","accepted":{"reason":"r","until":"-"},"category":"accounts"}
{"type":"finding","level":"INFO","id":"inf006i","check":"c5","message":"i","category":"logging"}
{"type":"finding","level":"ERROR","id":"err007e","check":"c6","message":"e","category":"tigris"}
{"type":"skip","check":"check_sudo","reason":"needs root"}
{"type":"skip","check":"check_x","reason":"live system"}
EOF

# -c, for the terminal: counts worst first, what was left out, the score,
# the ids by level and how to read the worst up; -C adds colour, and
# nothing else does
sh "$S" -c "$W/r.jsonl" > "$W/con.txt"; st=$?
[ $st -eq 0 ] && head -1 "$W/con.txt" | grep -q '^  2 ALERT   1 FAIL   3 WARN   1 INFO   1 ERROR$' &&
  grep -q '^  1 accepted finding left out (tigris-accept -l lists it)\.$' "$W/con.txt" &&
  grep -q '^  1 check needs root and was skipped: run Tigris as root to include it\.$' "$W/con.txt" &&
  grep -q '^  1 check needs a running system and was skipped\.$' "$W/con.txt" &&
  grep -q '^  Score 84 of 100 (100 minus 10 per ALERT id, 4 per FAIL id, 1 per WARN id)$' "$W/con.txt" &&
  grep -q '^  ALERT lin001a$' "$W/con.txt" && grep -q '^  WARN  ssh003w ssh004w$' "$W/con.txt" &&
  grep -q '^  tigris explain lin001a says' "$W/con.txt" &&
  ok "-c: counts, left out, score, ids by level, the worst to explain" || { bad "-c"; cat "$W/con.txt"; }
esc=`printf '\033'`
grep -q "$esc" "$W/con.txt" && bad "-c without -C has escape codes" || ok "-c without -C is plain text"
sh "$S" -c -C "$W/r.jsonl" | grep -q "${esc}\[1;31m2 ALERT${esc}\[0m" && ok "-C colours the levels" || bad "-C colours"

sh "$S" "$W/r.jsonl" > "$W/text.txt"; st=$?
[ $st -eq 0 ] && ok "text mode exits 0" || bad "text mode exits $st"
grep -q '^# Summary: 2 ALERT, 1 FAIL, 3 WARN, 1 INFO, 1 ERROR (4 distinct finding ids at WARN or above); 1 accepted finding left out; 2 checks skipped\.$' "$W/text.txt" &&
  ok "counts, distinct ids, accepted and skipped" || bad "summary line: `head -1 "$W/text.txt"`"
grep -q 'network 1 ALERT' "$W/text.txt" && grep -q 'other 1 ALERT' "$W/text.txt" && grep -q 'ssh 1 FAIL, 3 WARN' "$W/text.txt" &&
  grep -q 'tigris 1 ERROR' "$W/text.txt" && ok "by category, uncategorized as other" || bad "by category: `sed -n 2,3p "$W/text.txt"`"
grep -q '^# Score 84 of 100: 100 minus 10 per ALERT id, 4 per FAIL id,$' "$W/text.txt" &&
  grep -q '^#   1 per WARN id, each id once however often it is reported;$' "$W/text.txt" &&
  grep -q '^#   INFO, ERROR, accepted findings and skipped checks do not count\.$' "$W/text.txt" &&
  ok "the score with its formula" || bad "score lines: `grep '^# Score' "$W/text.txt"`"
grep -q '^#   ALERT (-10): lin001a$' "$W/text.txt" && grep -q '^#   FAIL (-4): lin002f$' "$W/text.txt" &&
  grep -q '^#   WARN (-2): ssh003w ssh004w$' "$W/text.txt" &&
  ok "each deduction names its ids" || bad "deduction lines: `grep '(-' "$W/text.txt"`"
awk 'NR > 1 && length > 76 { bad = 1 } END { exit bad }' "$W/text.txt" && ok "no wrapped line past 76 columns" || bad "a wrapped line past 76 columns"

# one finding: singulars, and nothing accepted or skipped to mention
cat > "$W/one.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"r1","tool":"tigris","version":"3.5.0","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-07T10:00:00Z"}
{"type":"finding","level":"WARN","id":"ssh003w","check":"c3","message":"w","category":"ssh"}
EOF
sh "$S" "$W/one.jsonl" > "$W/one.txt"
grep -q '^# Summary: 0 ALERT, 0 FAIL, 1 WARN, 0 INFO, 0 ERROR (1 distinct finding id at WARN or above)\.$' "$W/one.txt" &&
  grep -q '^# Score 99 of 100' "$W/one.txt" &&
  ok "one finding: singulars, score 99" || bad "one finding: `cat "$W/one.txt"`"

# no findings: 100, and no categories or deductions to list
cat > "$W/empty.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"r1","tool":"tigris","version":"3.5.0","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-07T10:00:00Z"}
EOF
sh "$S" "$W/empty.jsonl" > "$W/empty.txt"
grep -q '(0 distinct finding ids at WARN or above)\.' "$W/empty.txt" && grep -q '^# Score 100 of 100' "$W/empty.txt" &&
  ! grep -q 'by category\|(-' "$W/empty.txt" &&
  ok "no findings: score 100, nothing listed" || bad "empty: `cat "$W/empty.txt"`"

# many ids: the score counts each once, and the wrapped lists stay
# within 76 columns (the headline itself is one greppable line)
{ head -1 "$W/one.jsonl"
  i=0; while [ $i -lt 25 ]; do echo "{\"type\":\"finding\",\"level\":\"WARN\",\"id\":\"tst$(printf '%03d' $i)w\",\"check\":\"c\",\"message\":\"m\",\"category\":\"ssh\"}"; i=$((i+1)); done
} > "$W/many.jsonl"
sh "$S" "$W/many.jsonl" > "$W/many.txt"
grep -q '^# Score 75 of 100' "$W/many.txt" && grep -q '^#   WARN (-25): tst000w' "$W/many.txt" &&
  ok "25 distinct WARN ids score 75" || bad "many ids: `grep '^# Score' "$W/many.txt"`"
awk 'NR > 1 && length > 76 { bad = 1 } END { exit bad }' "$W/many.txt" && ok "wrapped id lists stay within 76 columns" || bad "a wrapped line past 76: `awk 'NR > 1 && length > 76' "$W/many.txt" | head -2`"

# usage errors
sh "$S" > /dev/null 2>&1; [ $? -eq 2 ] || { bad "no arguments exits $?"; }
sh "$S" "$W/no-such-file" > /dev/null 2>&1; [ $? -eq 2 ] || { bad "a missing report exits $?"; }
[ $fail -eq 0 ] && ok "usage errors exit 2"

# --- -j: the summary record's fields after its counts
sh "$S" -j "$W/r.jsonl" > "$W/frag.txt"; st=$?
[ $st -eq 0 ] || bad "-j exits $st"
if command -v python3 >/dev/null; then
  python3 - "$W/frag.txt" <<'EOF' && ok "-j splices into a summary record with distinct, categories and score" || bad "-j: `cat "$W/frag.txt"`"
import json, sys
frag = open(sys.argv[1]).read()
rec = json.loads('{"type":"summary","id":"r1","end":"2026-10-07T10:02:00Z","counts":{"ALERT":2,"FAIL":1,"WARN":4,"INFO":1,"ERROR":1}' + frag + ',"skipped":2}')
assert rec["distinct"] == {"ALERT": 1, "FAIL": 1, "WARN": 2}, rec["distinct"]
assert rec["categories"]["ssh"] == {"ALERT": 0, "FAIL": 1, "WARN": 3, "INFO": 0, "ERROR": 0}, rec["categories"]
assert rec["categories"]["other"]["ALERT"] == 1 and "accounts" not in rec["categories"], rec["categories"]
assert rec["score"]["value"] == 84 and rec["score"]["deducted"] == {"ALERT": 10, "FAIL": 4, "WARN": 2}, rec["score"]
assert "once" in rec["score"]["formula"] and "accepted" in rec["score"]["formula"], rec["score"]
assert rec["skipped"] == 2
EOF
else
  grep -q '"distinct":{"ALERT":1,"FAIL":1,"WARN":2}' "$W/frag.txt" && grep -q '"score":{"value":84' "$W/frag.txt" &&
    ok "-j fields (python3 absent, not parsed)" || bad "-j: `cat "$W/frag.txt"`"
fi

# --- a real run: the summary is at the end of both reports
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/log" "$W/run"
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"
sed 's/^\(Tiger_\(Check\|Run\|Deb\)_[A-Za-z0-9_]*\)=.*/\1=N/' "$W/tigerrc" > "$W/tigerrc.t"
echo "Tiger_Check_SYSTEM=Y" >> "$W/tigerrc.t"
chmod 600 "$W/tigerrc.t"
cat > "$W/plant" <<'EOF'
#!/bin/sh
basedir=${TIGERHOMEDIR:-.}
set --
. $basedir/config
. $BASEDIR/initdefs
while read level id msg
do
  message "$level" "$id" "" "$msg"
done < $BASEDIR/plant.list
EOF
chmod 755 "$W/plant"
echo "$W/plant" > "$W/check.d/plant"
printf 'WARN sum001w planted WARN\nWARN sum001w planted WARN again\nFAIL sum002f planted FAIL\n' > "$W/plant.list"
( cd "$W" && sh ./tigris -c tigerrc.t -q ) > "$W/out" 2> "$W/err"; st=$?
[ $st -eq 4 ] && ok "the planted run exits 4 (FAIL)" || bad "planted run exits $st: `cat "$W/err"`"
report=`ls -t "$W"/log/security.report.* 2>/dev/null | grep -v jsonl | head -1`
json=`ls -t "$W"/log/*.jsonl 2>/dev/null | head -1`
if [ -n "$report" ] && [ -n "$json" ]; then
  grep -q '^# Summary: 0 ALERT, 1 FAIL, 2 WARN, 0 INFO, 0 ERROR (2 distinct finding ids at WARN or above)\.$' "$report" &&
    grep -q '^# Score 95 of 100' "$report" &&
    ok "the text report ends with the summary and the score" || bad "text tail: `tail -8 "$report"`"
  summ_line=`grep -n '^# Summary:' "$report" | head -1 | cut -d: -f1`
  done_line=`grep -n 'Security report completed' "$report" | head -1 | cut -d: -f1`
  [ -n "$summ_line" ] && [ -n "$done_line" ] && [ "$summ_line" -lt "$done_line" ] &&
    ok "the summary comes before the report's last line" || bad "summary at $summ_line, last line at $done_line"
  grep -q '"distinct":{"ALERT":0,"FAIL":1,"WARN":1}' "$json" && grep -q '"score":{"value":95' "$json" &&
    grep -q '"categories":{"other":{"ALERT":0,"FAIL":1,"WARN":2,"INFO":0,"ERROR":0}}' "$json" &&
    ok "the JSON summary carries distinct, categories and score" || bad "JSON summary: `tail -1 "$json"`"
  tail -1 "$json" | grep -q ',"skipped":[0-9]*}$' && ok "the summary record still ends with skipped" || bad "JSON tail: `tail -1 "$json"`"
else
  bad "no reports in log/"; fail=1
fi

# with the JSON report off there is nothing to summarize from
rm -f "$W"/log/*
{ cat "$W/tigerrc.t"; echo "Tiger_Output_JSON=N"; } > "$W/tigerrc.n"; chmod 600 "$W/tigerrc.n"
( cd "$W" && sh ./tigris -c tigerrc.n -q ) > "$W/out" 2> "$W/err"; st=$?
[ $st -eq 4 ] || bad "JSON-off run exits $st"
report=`ls -t "$W"/log/security.report.* 2>/dev/null | head -1`
[ -n "$report" ] && ! grep -q '^# Summary:' "$report" && ok "with the JSON off, no summary" || bad "JSON-off tail: `tail -3 "$report"`"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- text.txt"; cat "$W/text.txt"; }
exit $fail
