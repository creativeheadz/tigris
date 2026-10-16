#!/bin/sh
#
# tests/missing_tools_check.sh - a host without strings (binutils)
#
# Minimal server images leave binutils out. The Linux checks' dispatcher
# once required strings, which it never used, so on such a host every
# Linux check (sysctl, firewall, PAM, sudo, updates, release...) was
# skipped behind one line of text, and the JSON summary said 0 ERROR: half
# of a fleet of Ubuntu servers looked clean that way in October 2026. This
# copies the tree with strings made unfindable and checks that the Linux
# checks run, and that a check that does need strings (the embedded paths)
# says so in the report.
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

# strings cannot be found, as on a host without binutils
for c in "$W/systems/Linux/2/config" "$W/systems/default/config"
do
  sed 's/^STRINGS=`findcmd strings`$/STRINGS=/' "$c" > "$c.new" && cat "$c.new" > "$c" && rm -f "$c.new"
done
grep -q '^STRINGS=$' "$W/systems/Linux/2/config" || { echo "FAIL could not take strings away"; exit 1; }

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
  for c in SYSTEM OS SYSCTL EMBEDDED; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/notools"
chmod 644 "$W/profiles/notools"
( cd "$W" && sh ./tigris --profile notools ) > "$W/out" 2>&1
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v jsonl | head -1`
json=`ls "$W"/log/*.jsonl 2>/dev/null | head -1`
[ -n "$report" ] && [ -n "$json" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }

# the sysctl check runs on every distribution (the release check only on
# those systems/Linux/2/check knows)
grep -q '^# Checking kernel and network hardening' "$report" &&
  ok "the Linux checks run without strings" || { bad "the Linux checks did not run:"; grep -n 'init001e\|^# ' "$report" | head; }
grep -q '^--ERROR-- \[init001e\] .*required command STRINGS' "$report" &&
  ok "the check that needs strings says so in the report" || bad "no init001e in the report"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
