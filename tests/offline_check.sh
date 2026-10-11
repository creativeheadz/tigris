#!/bin/sh
#
# tests/offline_check.sh - tigris --root: auditing a system that is not running
#
# Builds a small root in a directory: PAM stacks with pam_pwquality and
# pam_faillock, and a pwquality.conf that is an absolute link to another
# file of that root, setting minlen = 6. Runs tigris --root on it with a
# profile that leaves seven checks on: check_pam, which reads an offline
# root; check_timesync, check_ntp and check_rootkit, which read the running
# system; check_signatures, which cannot read an offline root; and check_ssh
# and check_sudo, which can but need root. check_pam must report the root's
# minimum length, read through the link inside the root; check_timesync,
# check_ntp, check_rootkit and check_signatures must be skipped, each with
# its reason, and check_ssh and check_sudo too when this is not root; the run
# record names the root, and the run exits 3 (a
# WARN): a check that does not apply to an offline root is not one that
# failed to run. Then
# util/rootpath on its own (links that would leave the root, loops), the
# paths --root refuses (con014e), and tigris-diff's notes on two runs, one
# of the root and one of the running system. Needs no root.
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
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"

# The root: an unknown distribution, so no package manager is asked
R=$W/img
mkdir -p "$R/etc/pam.d" "$R/etc/security" "$R/usr/lib"
printf 'ID=tigristest\nNAME="Tigris test root"\n' > "$R/usr/lib/os-release"
ln -s ../usr/lib/os-release "$R/etc/os-release"
echo 'password requisite pam_pwquality.so retry=3' > "$R/etc/pam.d/common-password"
echo 'auth required pam_faillock.so preauth' > "$R/etc/pam.d/common-auth"
echo 'minlen = 6' > "$R/etc/security/pwquality-real.conf"
# absolute: followed on this host it would name a file that is not there
ln -s /etc/security/pwquality-real.conf "$R/etc/security/pwquality.conf"

# Every Tiger_Check_* off but seven, and the Debian ones off
{
  sed -n 's/^\(Tiger_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigerrc"
  echo 'Tiger_Deb_CheckMD5Sums=N'; echo 'Tiger_Deb_NoPackFiles=N'; echo 'Tiger_Deb_StatOverride=N'
  echo 'Tiger_Check_SYSTEM=Y'; echo 'Tiger_Check_PAM=Y'; echo 'Tiger_Check_TIMESYNC=Y'; echo 'Tiger_Check_SUDO=Y'; echo 'Tiger_Check_SSH=Y'; echo 'Tiger_Check_SIGNATURES=Y'; echo 'Tiger_Check_NTP=Y'; echo 'Tiger_Check_ROOTKIT=Y'
} > "$W/profiles/offline"
chmod 644 "$W/profiles/offline"

( cd "$W" && sh ./tigris -q --profile offline --root "$R" ) > "$W/out" 2>&1; st=$?
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$report" ] && [ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }

grep -q '"id":"pam002w".*"message":"New passwords may be as short as 6 characters."' "$json" &&
  ok "check_pam read the root's pwquality.conf, through an absolute link inside the root" || { bad "pam002w"; grep pam "$json"; }
grep -q '"id":"pam00[13]w"' "$json" && bad "pam001w or pam003w: the root's stacks were not the ones read" ||
  ok "the root's PAM stacks were read: quality and lockout found"
grep -q "^# Skipped check_timesync: it reads the running system, and this audit is of $R\.$" "$report" &&
  grep -q "^# Skipped check_ntp: it reads the running system, and this audit is of $R\.$" "$report" &&
  grep -q "^# Skipped check_rootkit: it reads the running system, and this audit is of $R\.$" "$report" &&
  grep -q '^# Skipped check_signatures: it cannot read an offline root yet\.$' "$report" &&
  ok "three live-system checks and one not offline yet are skipped, each saying why" || { bad "report lines"; grep Skipped "$report"; }
if [ "`id -u`" = 0 ]; then
  want=4
  grep -q 'Skipped check_s\(sh\|udo\)' "$report" && bad "as root, check_ssh or check_sudo was skipped" || ok "as root, check_ssh and check_sudo (offline, need root) ran"
else
  want=6
  grep -q '^# Skipped check_ssh: it needs root' "$report" && grep -q '{"type":"skip","check":"check_ssh","reason":"needs root"}' "$json" &&
    grep -q '{"type":"skip","check":"check_sudo","reason":"needs root"}' "$json" &&
    ok "as a user, check_ssh and check_sudo (offline, need root) are skipped for root" || { bad "check_ssh/check_sudo as a user"; grep Skipped "$report"; }
fi
grep -q '{"type":"skip","check":"check_timesync","reason":"live system"}' "$json" &&
  grep -q '{"type":"skip","check":"check_ntp","reason":"live system"}' "$json" &&
  grep -q '{"type":"skip","check":"check_rootkit","reason":"live system"}' "$json" &&
  grep -q '{"type":"skip","check":"check_signatures","reason":"not offline yet"}' "$json" &&
  grep -q "\"type\":\"summary\".*\"skipped\":$want}" "$json" &&
  ok "a skip record each in the JSON, \"skipped\":$want in the summary" || { bad "skip records"; grep '"skip' "$json"; tail -1 "$json"; }
grep -q "\"type\":\"run\".*\"root\":\"$R\"" "$json" && ok "the run record names the root" || { bad "run record"; head -1 "$json"; }
[ "$st" = 3 ] && ok "exit status 3: the WARN; skipping what does not apply to an offline root is not an error" || bad "exit status $st"
grep -q "Checking time synchronisation\|signature check of system binaries" "$report" && bad "a skipped check ran" || ok "the skipped checks did not run"
sh "$W/tests/schema_check.sh" "$json" > "$W/schema.out" 2>&1
case $? in
  0) ok "the report validates" ;;
  2) ok "(the schema is not checked here: `tail -1 "$W/schema.out"`)" ;;
  *) bad "schema"; cat "$W/schema.out" ;;
esac

# util/rootpath on its own
T=$W/rp
mkdir -p "$T/usr/bin" "$T/etc" "$T/a/b" "$T/proc/self"
ln -s usr/bin "$T/bin"; : > "$T/usr/bin/ls"; : > "$T/etc/shadow"
ln -s /etc/shadow "$T/etc/abs"; ln -s ../../../../../etc/shadow "$T/a/b/up"
ln -s loop2 "$T/loop1"; ln -s loop1 "$T/loop2"; ln -s /x "$T/proc/self/cwd"
printf '/bin/ls\n/etc/abs\n/a/b/up\n/loop1\n/usr/../../etc/./shadow\n' | sh "$W/util/rootpath" "$T/" "$W/links" > "$W/rp.out"
printf '%s\n' "$T/usr/bin/ls" "$T/etc/shadow" "$T/etc/shadow" "" "$T/etc/shadow" > "$W/rp.want"
[ "`cat "$W/rp.out"`" = "`cat "$W/rp.want"`" ] &&
  ok "rootpath: a relative link, an absolute one, .. past the top and a loop, all inside the root" || { bad "rootpath"; cat "$W/rp.out"; }
grep -q '/proc' "$W/links" && bad "rootpath listed links under /proc" || ok "rootpath leaves /proc out of the links it lists"
echo /bin/ls | sh "$W/util/rootpath" "$T" "$W/links" | grep -qx "$T/usr/bin/ls" && ok "rootpath reuses its table" || bad "rootpath table"

# What --root refuses
( cd "$W" && sh ./tigris -q --root "$W/none" ) > "$W/err1" 2>&1; st1=$?
mkdir -p "$W/sp ace/etc"
( cd "$W" && sh ./tigris -q --root "$W/sp ace" ) > "$W/err2" 2>&1; st2=$?
[ "$st1" = 1 ] && grep -q "\[con014e\] $W/none is not the root of a system to audit" "$W/err1" &&
  [ "$st2" = 1 ] && grep -q '\[con014e\] .* is not a path --root can take' "$W/err2" &&
  ok "con014e: no etc directory, and a space in the path; exit 1" || { bad "con014e"; cat "$W/err1" "$W/err2"; }
( cd "$W" && sh ./tigris explain con014e ) 2>&1 | grep -q 'is not the root of a system Tigris can' && ok "tigris explain con014e" || bad "no explanation for con014e"

# tigris-diff: a run of the root against a run of the running system
cat > "$W/live.jsonl" <<'EOF'
{"type":"run","schema":1,"id":"a","tool":"tigris","version":"x","host":"h","os":"Linux","release":"r","arch":"x86_64","config":"./tigerrc","start":"2026-10-07T10:00:00Z"}
{"type":"finding","level":"WARN","id":"time001w","check":"check_timesync","message":"No time synchronisation daemon is running."}
{"type":"finding","level":"WARN","id":"pam002w","check":"check_pam","message":"New passwords may be as short as 6 characters."}
{"type":"summary","id":"a","end":"2026-10-07T10:01:00Z","counts":{"ALERT":0,"FAIL":0,"WARN":2,"INFO":0,"ERROR":0},"skipped":0}
EOF
sh "$W/tigris-diff" "$W/live.jsonl" "$json" > "$W/diff.out"
grep -q "note: the runs used different configurations (./tigerrc, .* of $R)" "$W/diff.out" &&
  grep -q 'note: skipped in either run (not root, or a check that cannot read an offline root), so left out of both sides: .*check_timesync' "$W/diff.out" &&
  grep -q 'new (0)' "$W/diff.out" && grep -q 'resolved (0)' "$W/diff.out" &&
  ok "tigris-diff: the root is part of the configuration, live-only checks are set aside" || { bad "diff"; cat "$W/diff.out"; }

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/out"; }
exit $fail
