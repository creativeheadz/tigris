#!/bin/sh
#
# tests/nonroot_check.sh - checks that need root are skipped, and said to be
#
# Runs tigris with a profile that leaves four checks on: check_ssh (started
# through run_script) and check_sudo (started by systems/Linux/2/check),
# whose headers say "# Tigris: needs root", and check_secureboot and
# check_timesync, which do not. As an ordinary user the first two must be
# skipped: a "# Skipped" line each in the report, a skip record each in
# the JSON, "skipped":2 in the summary, an exit status of at least 2. As
# root nothing is skipped. Then tigris-diff, given a root run with a
# check_sudo finding and a user run that skipped check_sudo, must not call
# that finding resolved.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
uid=`id -u`
[ "$uid" = 0 ] && chown -R 0:0 "$W"

# Every Tiger_Check_* off but four, and the Debian ones off
{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Deb_CheckMD5Sums=N'; echo 'Tiger_Deb_NoPackFiles=N'; echo 'Tiger_Deb_StatOverride=N'
  echo 'Tiger_Check_SYSTEM=Y'; echo 'Tiger_Check_SSH=Y'; echo 'Tiger_Check_SUDO=Y'
  echo 'Tiger_Check_SECUREBOOT=Y'; echo 'Tiger_Check_TIMESYNC=Y'
} > "$W/profiles/fourchecks"
chmod 644 "$W/profiles/fourchecks"

( cd "$W" && sh ./tigris -q --profile fourchecks ) > "$W/out" 2>&1; st=$?
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$report" ] && [ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }

if [ "$uid" != 0 ]; then
  grep -q '^# Skipped check_ssh: it needs root' "$report" && grep -q '^# Skipped check_sudo: it needs root' "$report" &&
    ok "as a user: check_ssh (run_script) and check_sudo (systems/Linux/2/check) skipped, in the report" || { bad "report lines"; grep Skipped "$report"; }
  grep -q '{"type":"skip","check":"check_ssh","reason":"needs root"}' "$json" && grep -q '"check":"check_sudo","reason":"needs root"' "$json" &&
    ok "a skip record each in the JSON" || { bad "skip records"; grep skip "$json"; }
  grep -q '"type":"summary".*"skipped":2}' "$json" && ok "the summary counts 2 skipped" || { bad "summary"; tail -1 "$json"; }
  [ "$st" -ge 2 ] && ok "exit status $st: checks could not run" || bad "exit status $st"
  grep -q '"check":"check_s\(sh\|udo\)","message"' "$json" && bad "a skipped check reported findings" || ok "no findings from the skipped checks"
  grep -q 'Checking Secure Boot\|Checking time synchronisation' "$report" && ok "checks that do not need root still ran" || bad "unmarked checks did not run"
else
  [ "`grep -c '^# Skipped ' "$report"`" = 0 ] && grep -q '"type":"summary".*"skipped":0}' "$json" &&
    ok "as root: nothing skipped, \"skipped\":0" || { bad "root skipped something"; grep Skipped "$report"; }
fi
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1
case $? in
  0) ok "the report validates" ;;
  2) ok "(the schema is not checked here: `tail -1 "$W/schema.out"`)" ;;
  *) bad "schema"; cat "$W/schema.out" ;;
esac

# tigris-diff: a check skipped in one run is left out of both sides
cat > "$W/a.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"a","tool":"tigris","version":"x","host":"h","os":"Linux","release":"r","arch":"x86_64","config":"./tigerrc","start":"2026-10-07T10:00:00Z"}
{"type":"finding","level":"WARN","id":"sudo001w","check":"check_sudo","message":"alice may run any command as root with sudo, without a password: whoever gets that account's session gets root."}
{"type":"finding","level":"WARN","id":"time001w","check":"check_timesync","message":"No time synchronisation daemon is running."}
{"type":"summary","id":"a","end":"2026-10-07T10:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":2,"INFO":0,"ERROR":0},"skipped":0}
EOF
cat > "$W/b.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"b","tool":"tigris","version":"x","host":"h","os":"Linux","release":"r","arch":"x86_64","config":"./tigerrc","start":"2026-10-07T11:00:00Z"}
{"type":"skip","check":"check_sudo","reason":"needs root"}
{"type":"summary","id":"b","end":"2026-10-07T11:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":0,"INFO":0,"ERROR":0},"skipped":1}
EOF
sh "$W/tigris-diff" -j "$W/a.jsonl" "$W/b.jsonl" > "$W/diff.json"
grep -q '"resolved":\[{"type":"finding","level":"WARN","id":"time001w"' "$W/diff.json" && ! grep -q 'sudo001w' "$W/diff.json" &&
  grep -q '"skipped_checks":\["check_sudo"\]' "$W/diff.json" &&
  ok "tigris-diff: the skipped check's finding is not resolved; the other one is" || { bad "diff"; cat "$W/diff.json"; }
sh "$W/tigris-diff" "$W/a.jsonl" "$W/b.jsonl" | grep -q 'note: skipped in either run (not root, or a check that cannot read an offline root), so left out of both sides: check_sudo' &&
  ok "tigris-diff's text says so" || bad "diff text"
sh "$W/tests/schema_check.sh" "$W/a.jsonl" > /dev/null 2>&1; sa=$?
sh "$W/tests/schema_check.sh" "$W/b.jsonl" > /dev/null 2>&1; sb=$?
if [ $sa = 0 ] && [ $sb = 0 ]; then ok "both hand-made reports validate"
elif [ $sa = 2 ] && [ $sb = 2 ]; then ok "(the schema is not checked here)"
else bad "schema of the hand-made reports"; fi

[ $fail -eq 0 ] && echo "PASS"
exit $fail
