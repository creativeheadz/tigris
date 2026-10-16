#!/bin/sh
#
# tests/diff_check.sh - tigris-diff against two synthetic runs
#
# Two JSON Lines reports that share some findings, lose one, gain one, and
# differ in an INFO line. Checks the text, the exit status, -a, the JSON
# mode (parsed with python3 when available) and the "no files" lookup in
# a log directory.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
D=$TIGER/tigris-diff
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

mkdir -p "$W/log"
cat > "$W/log/security.report.box.261004-10:00.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"run-a","tool":"tigris","version":"3.2.4","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-04T10:00:00Z"}
{"type":"finding","level":"WARN","id":"ssh004w","check":"check_ssh","message":"sshd: passwordauthentication is yes: passwords are accepted for login"}
{"type":"finding","level":"FAIL","id":"lin016f","check":"check_network_config","message":"The system permits source routing from incoming packets"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"/etc/odd \"quoted\" caf\u00e9 is a dangling symlink."}
{"type":"finding","level":"INFO","id":"cron004w","check":"check_crontabs","message":"Root crontab does not exist"}
{"type":"summary","id":"run-a","end":"2026-10-04T10:02:00Z","counts":{"ALERT":0,"FAIL":1,"WARN":2,"INFO":1,"ERROR":0}}
EOF
cat > "$W/log/security.report.box.261004-11:00.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"run-b","tool":"tigris","version":"3.2.4","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-04T11:00:00Z"}
{"type":"finding","level":"FAIL","id":"lin016f","check":"check_network_config","message":"The system permits source routing from incoming packets"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"/etc/odd \"quoted\" caf\u00e9 is a dangling symlink (still)."}
{"type":"finding","level":"WARN","id":"dev004w","check":"check_devices","message":"/dev/kmsg is world readable"}
{"type":"finding","level":"INFO","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd' is listening on socket 22 (TCP) on every interface."}
{"type":"summary","id":"run-b","end":"2026-10-04T11:02:00Z","counts":{"ALERT":0,"FAIL":1,"WARN":2,"INFO":1,"ERROR":0}}
EOF
A="$W/log/security.report.box.261004-10:00.jsonl"; B="$W/log/security.report.box.261004-11:00.jsonl"

sh "$D" "$A" "$B" > "$W/out.txt"; st=$?
[ $st -eq 1 ] && ok "exit 1 when something is new" || bad "exit status $st, wanted 1"
grep -q '^  new (2):' "$W/out.txt" && grep -q '+ WARN  dev004w /dev/kmsg is world readable' "$W/out.txt" && ok "the new finding is listed" || bad "new finding"
grep -q '^  resolved (2):' "$W/out.txt" && grep -q -- '- WARN  ssh004w sshd: passwordauthentication' "$W/out.txt" && ok "the resolved finding is listed" || bad "resolved finding"
grep -q 'unchanged: 1 (INFO not compared' "$W/out.txt" && ok "one unchanged, INFO left out" || bad "unchanged count"
grep -F -q "$(printf '/etc/odd "quoted" caf\351 is a dangling symlink (still)')" "$W/out.txt" && ok "message with escapes decoded for display" || bad "decoding"
grep -q 'Tigris diff: box 2026-10-04T10:00:00Z -> box 2026-10-04T11:00:00Z' "$W/out.txt" && ok "header names host and times" || bad "header"
grep -q 'cron004w\|lin002i' "$W/out.txt" && bad "INFO leaked into the default diff" || ok "INFO not in the default diff"

sh "$D" -a "$A" "$B" > "$W/all.txt"
grep -q '^  new (3):' "$W/all.txt" && grep -q 'lin002i' "$W/all.txt" && grep -q -- '- INFO  cron004w' "$W/all.txt" && ok "-a compares INFO too" || bad "-a"

sh "$D" "$B" "$B" > "$W/same.txt"; st=$?
[ $st -eq 0 ] && grep -q 'new (0)' "$W/same.txt" && ok "a run against itself: nothing new, exit 0" || bad "self diff"
# an empty old report (a run that died before writing anything): every
# finding of the new run is new, none resolved
: > "$W/empty.jsonl"
sh "$D" "$W/empty.jsonl" "$B" > "$W/empty.txt"; st=$?
[ $st -eq 1 ] && grep -q '^  new (3):' "$W/empty.txt" && grep -q '^  resolved (0):' "$W/empty.txt" &&
  ok "an empty old report: the new run's findings are new" || { bad "empty old report (exit $st)"; cat "$W/empty.txt"; }

( cd "$W" && sh "$D" ) > "$W/auto.txt"
grep -q 'dev004w' "$W/auto.txt" && grep -q 'ssh004w' "$W/auto.txt" && ok "no arguments: the two newest runs in ./log" || bad "auto lookup"
( cd "$W" && sh "$D" "$B" ) > "$W/one.txt"
grep -q 'dev004w' "$W/one.txt" && ok "one argument: that run against the one before" || bad "one-argument lookup"

sh "$D" -j "$A" "$B" > "$W/diff.json"
if command -v python3 >/dev/null; then
  python3 - "$W/diff.json" <<'EOF' && ok "-j is one JSON object with run records and raw findings" || bad "-j"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["type"] == "diff" and d["from"]["id"] == "run-a" and d["to"]["id"] == "run-b"
assert [f["id"] for f in d["new"]] == ["fsys013w", "dev004w"] and [f["id"] for f in d["resolved"]] == ["ssh004w", "fsys013w"]
assert d["unchanged"] == 1
assert d["resolved"][0]["check"] == "check_ssh"
EOF
else
  grep -q '"type":"diff"' "$W/diff.json" && ok "-j writes a diff object (python3 absent, not parsed)" || bad "-j"
fi

# A full run against a quick one: the quick run did not scan the file
# system, so its missing fsys* findings are neither resolved nor new.
# (3.3 reports say tigerrc: the name is what the run used, opaque to the diff)
cat > "$W/full.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"full","tool":"tigris","version":"3.3","host":"box","os":"Linux","release":"7.0","arch":"x86_64","config":"tigerrc","filesystem_scan":true,"start":"2026-10-05T10:00:00Z"}
{"type":"finding","level":"WARN","id":"fsys013w","check":"find_files","message":"/etc/x is a dangling symlink."}
{"type":"finding","level":"WARN","id":"ssh008w","check":"check_ssh","message":"x11"}
{"type":"summary","id":"full","end":"2026-10-05T10:02:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":2,"INFO":0,"ERROR":0}}
EOF
cat > "$W/quick.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"quick","tool":"tigris","version":"3.3","host":"box","os":"Linux","release":"7.0","arch":"x86_64","config":"tigerrc-quick","filesystem_scan":false,"start":"2026-10-05T11:00:00Z"}
{"type":"finding","level":"WARN","id":"ssh008w","check":"check_ssh","message":"x11"}
{"type":"summary","id":"quick","end":"2026-10-05T11:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
sh "$D" "$W/full.jsonl" "$W/quick.jsonl" > "$W/fq.txt"; st=$?
grep -q 'fsys013w' "$W/fq.txt" && bad "full -> quick reports the unscanned fsys finding" || ok "full -> quick: the fsys finding is set aside, not resolved"
[ $st -eq 0 ] && grep -q 'unchanged: 1' "$W/fq.txt" && ok "full -> quick: nothing new, the shared finding unchanged" || bad "full -> quick exit $st or counts"
grep -q 'note: the second run did not scan the file system' "$W/fq.txt" && ok "the text says which run skipped the scan" || bad "scan note"
sh "$D" "$W/quick.jsonl" "$W/quick.jsonl" > "$W/qq.txt"
grep -q 'note: neither run scanned the file system, so its findings' "$W/qq.txt" && ok "and says so plainly when neither did" || bad "both-quick note: `grep note "$W/qq.txt"`"
grep -q 'note: the runs used different configurations (tigerrc, tigerrc-quick)' "$W/fq.txt" && ok "the text says the configurations differ" || bad "config note"
sh "$D" "$W/quick.jsonl" "$W/full.jsonl" > "$W/qf.txt"; st=$?
[ $st -eq 0 ] && ! grep -q 'fsys013w' "$W/qf.txt" && ok "quick -> full: the fsys finding is not new" || bad "quick -> full exit $st"
sh "$D" -j "$W/full.jsonl" "$W/quick.jsonl" > "$W/fq.json"
grep -q '"set_aside":\["fsys"\]' "$W/fq.json" && grep -q '"configs_differ":true' "$W/fq.json" && ok "-j records set_aside and configs_differ" || bad "-j markers: `cat "$W/fq.json"`"
sh "$D" "$W/full.jsonl" "$W/full.jsonl" | grep -q 'note:' && bad "a run against itself gets a note" || ok "same run, same config: no notes"

# Old minute-resolution names next to new ones with seconds: the byte
# sort still puts them in time order (an old-style name sorts first
# within its minute, as if its unknown seconds were :00), so the auto
# lookup picks the two newest.
mkdir -p "$W/mix/log"
cat > "$W/mix/log/security.report.box.261004-10:00.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"mix-old","tool":"tigris","version":"3.3","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-04T10:00:00Z"}
{"type":"finding","level":"WARN","id":"ssh008w","check":"check_ssh","message":"old style minute stamp"}
{"type":"summary","id":"mix-old","end":"2026-10-04T10:00:30Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
cat > "$W/mix/log/security.report.box.261004-10:00:30.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"mix-mid","tool":"tigris","version":"3.3","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-04T10:00:30Z"}
{"type":"finding","level":"WARN","id":"ssh009w","check":"check_ssh","message":"same minute with seconds"}
{"type":"summary","id":"mix-mid","end":"2026-10-04T10:00:40Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
cat > "$W/mix/log/security.report.box.261004-10:01:05.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"mix-new","tool":"tigris","version":"3.3","host":"box","os":"Linux","release":"7.0","arch":"x86_64","start":"2026-10-04T10:01:05Z"}
{"type":"finding","level":"WARN","id":"ssh012w","check":"check_ssh","message":"next minute with seconds"}
{"type":"summary","id":"mix-new","end":"2026-10-04T10:01:10Z","counts":{"ALERT":0,"FAIL":0,"WARN":1,"INFO":0,"ERROR":0}}
EOF
( cd "$W/mix" && sh "$D" ) > "$W/mix.txt"
grep -q 'Tigris diff: box 2026-10-04T10:00:30Z -> box 2026-10-04T10:01:05Z' "$W/mix.txt" && ok "mixed old and new names: the two newest are picked" || bad "mixed lookup: `head -1 "$W/mix.txt"`"
grep -q -- '- WARN  ssh009w' "$W/mix.txt" && grep -q '+ WARN  ssh012w' "$W/mix.txt" && ! grep -q 'ssh008w' "$W/mix.txt" && ok "mixed lookup compares the right pair" || bad "mixed pair"

# A new finding that is already accepted is listed, marked, and is not
# "something new" for the exit status; an open one next to it still is.
{ sed '$d' "$B"; echo '{"type":"finding","level":"FAIL","id":"lin005f","check":"deb_checkmd5sums","message":"/usr/bin/x differs","accepted":{"reason":"local build","until":"-"}}'; tail -1 "$B"; } > "$W/acc.jsonl"
sh "$D" "$B" "$W/acc.jsonl" > "$W/acc.txt"; st=$?
[ $st -eq 0 ] && grep -q '+ FAIL  lin005f /usr/bin/x differs (accepted)' "$W/acc.txt" && ok "an accepted new finding is marked and does not make the exit 1" || bad "accepted new finding: status $st, `grep lin005f "$W/acc.txt"`"
{ sed '$d' "$W/acc.jsonl"; echo '{"type":"finding","level":"WARN","id":"ssh012w","check":"check_ssh","message":"open one"}'; tail -1 "$B"; } > "$W/acc2.jsonl"
sh "$D" "$B" "$W/acc2.jsonl" > /dev/null; st=$?
[ $st -eq 1 ] && ok "an open new finding next to it still does" || bad "open next to accepted: status $st"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out.txt"; cat "$W/out.txt"; }
exit $fail
