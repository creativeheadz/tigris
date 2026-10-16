#!/bin/sh
#
# tests/exit_check.sh - the exit status of tigris, -q and --since
#
# Runs the real tigris from a copy of the tree with every check switched
# off except check_system, and plants findings through check.d: a table
# there names a script that emits whatever plant.list says. So each run
# takes a fraction of a second, needs no root, and its findings are known.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/log" "$W/run"
# as root, the tree must be root's for Tigris to run its scripts
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# Every switch off, then check_system on
sed 's/^\(Tigris_\(Check\|Run\|Deb\)_[A-Za-z0-9_]*\)=.*/\1=N/' "$W/tigris.conf" > "$W/tigris.conf.t"
echo "Tigris_Check_SYSTEM=Y" >> "$W/tigris.conf.t"
chmod 600 "$W/tigris.conf.t"

cat > "$W/plant" <<'EOF'
#!/bin/sh
# Emits the findings listed in plant.list, one "LEVEL id message" a line
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

# plant LEVEL:id ... ; then run tigris with the given options, from $W.
# Leaves the exit status in $st and stdout in $W/out.
plant() { : > "$W/plant.list"; for f; do echo "${f%%:*} ${f#*:} planted ${f%%:*}" >> "$W/plant.list"; done; }
run() { ( cd "$W" && sh ./tigris -c tigris.conf.t "$@" ) > "$W/out" 2> "$W/err"; st=$?; }
expect() {  # expect STATUS "what" options...
  want=$1; what=$2; shift 2
  run "$@"
  [ "$st" = "$want" ] && ok "$what: exit $st" || bad "$what: exit $st, wanted $want"
}

# --- the worst finding sets the status
plant;                                expect 0 "no findings"
plant INFO:test004i;                  expect 0 "INFO only"
plant ERROR:test005e;                 expect 2 "a check could not run (ERROR)"
plant ERROR:test005e WARN:test001w;   expect 3 "WARN is worse than ERROR"
plant WARN:test001w FAIL:test002f;    expect 4 "FAIL"
plant WARN:test001w ALERT:test003a;   expect 5 "ALERT"

# --- an accepted finding does not count
printf 'test002f\t-\t-\tknown and accepted\n' > "$W/tigris.accepted"
plant FAIL:test002f;                  expect 0 "an accepted FAIL"
plant FAIL:test002f WARN:test001w;    expect 3 "an accepted FAIL next to an open WARN"
rm -f "$W/tigris.accepted"

# --- an ERROR line that is only echoed, not a message(), counts too
echo "$W/no-such-check" > "$W/check.d/plant2"
plant;                                expect 2 "a check.d entry that cannot be found"
rm -f "$W/check.d/plant2"

# --- a check run_script cannot run is a finding in the JSON as well
sed 's/^Tigris_Check_ETCISSUE=.*/Tigris_Check_ETCISSUE=Y/' "$W/tigris.conf.t" > "$W/tigris.conf.i"; chmod 600 "$W/tigris.conf.i"
chmod 644 "$W/scripts/check_issue"
plant
( cd "$W" && sh ./tigris -c tigris.conf.i ) > "$W/out" 2>&1; st=$?
j=`ls -t "$W"/log/*.jsonl | head -1`
[ "$st" = 2 ] && grep -q '"level":"ERROR","id":"misc025e"' "$j" && ok "a check that is not executable: exit 2, misc025e in the JSON" || bad "not-executable check: exit $st, `grep -c misc025e "$j"` misc025e records"
chmod 755 "$W/scripts/check_issue"

# --- -q prints nothing
plant WARN:test001w
expect 3 "-q" -q
[ -s "$W/out" ] && bad "-q printed: `head -2 "$W/out"`" || ok "-q printed nothing"

# --- --since: only what changed. Report names carry seconds, so each run
# waits for the next second to have a name of its own.
rm -f "$W"/log/*
plant WARN:test001w
# no baseline: every finding is new, so the status is the whole run's
expect 3 "--since last with no earlier run" -q --since last
grep -q '^No earlier run' "$W/out" && ok "it says there was no earlier run" || bad "no-baseline note: `cat "$W/out"`"
base=`ls "$W"/log/*.jsonl`

sleep 1
plant WARN:test001w
expect 0 "--since FILE, nothing changed" -q --since "$base"
[ -s "$W/out" ] && bad "-q --since printed with nothing changed: `head -3 "$W/out"`" || ok "-q --since printed nothing when nothing changed"

sleep 1
plant WARN:test001w FAIL:test002f
expect 4 "--since last, a new FAIL" -q --since last
grep -q '+ FAIL  test002f planted FAIL' "$W/out" && ! grep -q 'test001w' "$W/out" && ok "only the new finding is printed" || bad "new finding output: `cat "$W/out"`"

sleep 1
plant WARN:test001w
expect 0 "--since last, the FAIL resolved" -q --since last
grep -q -- '- FAIL  test002f' "$W/out" && ok "the resolved finding is printed" || bad "resolved output: `cat "$W/out"`"

sleep 1
printf 'test003a\t-\t-\tknown and accepted\n' > "$W/tigris.accepted"
plant WARN:test001w ALERT:test003a
expect 0 "--since last, the only new finding is accepted" -q --since last
grep -q 'test003a planted ALERT (accepted)' "$W/out" && ok "it is printed, marked accepted" || bad "accepted new output: `cat "$W/out"`"
rm -f "$W/tigris.accepted"

# --- --since that cannot work stops before the run
expect 1 "--since a file that does not exist" --since "$W/nope.jsonl"
grep -q 'init012e' "$W/out" && ok "it says so (init012e)" || bad "init012e: `cat "$W/out"`"
expect 1 "--since with no run named" --since
grep -q 'con012e' "$W/out" && ok "it says so (con012e)" || bad "con012e: `cat "$W/out"`"
{ cat "$W/tigris.conf.t"; echo "Tigris_Output_JSON=N"; } > "$W/tigris.conf.n"; chmod 600 "$W/tigris.conf.n"
( cd "$W" && sh ./tigris -c tigris.conf.n --since last ) > "$W/out" 2>&1; st=$?
[ "$st" = 1 ] && grep -q 'init011e' "$W/out" && ok "--since with the JSON report off: exit 1 (init011e)" || bad "--since without JSON: exit $st"

# -c with a path holding a space and a double quote: the tigris.conf is read
# (unquoted, the test failed and every check ran, the file system scan
# included), and the run record carries the path as valid JSON
RCD="$W/rc dir \"q\""
mkdir -p "$RCD"; cp "$W/tigris.conf.t" "$RCD/tigris.conf"; chmod 755 "$RCD"; chmod 600 "$RCD/tigris.conf"
rm -f "$W"/log/*.jsonl
( cd "$W" && sh ./tigris -q -c "$RCD/tigris.conf" ) > "$W/out" 2>&1
j=`ls "$W"/log/*.jsonl 2>/dev/null | tail -1`
if [ -z "$j" ]; then
  bad "-c with a space and a quote: no JSON report"
elif command -v python3 >/dev/null 2>&1; then
  python3 -I - "$j" "$RCD/tigris.conf" <<'EOF' && ok "-c with a space and a quote: read, and the run record is valid JSON naming it" || bad "-c with a space and a quote: `head -1 "$j"`"
import json, sys
run = json.loads(open(sys.argv[1]).readline())
assert run["config"] == sys.argv[2], run["config"]
assert run["filesystem_scan"] is False, run
EOF
else
  grep -q '"filesystem_scan":false' "$j" && ok "-c with a space and a quote: read (python3 absent, JSON not parsed)" || bad "-c with a space and a quote"
fi

# the usage and -v name the version (the usage once came before it was read)
v=`cat "$W/version.h"`
( cd "$W" && sh ./tigris -h ) > "$W/out" 2>&1; st=$?
[ "$st" = 0 ] && grep -qF "Tigris, version $v" "$W/out" && ok "-h names the version" || bad "-h: exit $st, `grep 'version' "$W/out" | head -1`"
( cd "$W" && sh ./tigris --help ) > "$W/out" 2>&1; st=$?
[ "$st" = 0 ] && grep -qF "Tigris, version $v" "$W/out" && ! grep -q con006e "$W/out" && ok "--help is -h" || bad "--help: exit $st"
( cd "$W" && sh ./tigris -v ) > "$W/out" 2>&1
grep -qF "Tigris, version $v" "$W/out" && ok "-v names the version" || bad "-v: `tail -1 "$W/out"`"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- last stdout"; cat "$W/out"; echo "--- last stderr"; cat "$W/err"; }
exit $fail
