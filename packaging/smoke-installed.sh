#!/bin/sh
#
# packaging/smoke-installed.sh - the installed package runs
#
# Runs as root on a machine (or container) with the tigris package
# installed: the entry points answer, a real offline run finishes and
# writes its reports under /var/log/tigris, --since compares with the
# earlier run, and the diff and accept defaults name the tigris paths.
#
fail=0
expect()
{
  if eval "$1"; then
    echo "ok   $2"
  else
    echo "FAIL $2"
    fail=1
  fi
}

[ "`id -u`" = 0 ] || { echo "SKIP: must run as root"; exit 2; }
command -v tigris >/dev/null 2>&1 || { echo "SKIP: tigris is not installed"; exit 2; }

tigris -h >/dev/null 2>&1
expect "[ $? -eq 0 ]" "tigris -h runs"
tigris explain lin002i 2>/dev/null | grep -q 'Severity:'
expect "[ $? -eq 0 ]" "tigris explain finds its engine"

W=`mktemp -d`
trap 'rm -rf "$W"' 0
mkdir -p "$W/root/etc" "$W/root/bin"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$W/root/etc/passwd"
printf 'root:x:0:\n' > "$W/root/etc/group"
printf '#!/bin/sh\necho hi\n' > "$W/root/bin/hi"
chmod 755 "$W/root/bin/hi"

tigris -q -E --root "$W/root" >"$W/run1.out" 2>&1; st=$?
case $st in 0|3|4|5) expect true "a real run finishes";; *) expect false "a real run finishes (exit $st)";; esac
sleep 2 # report names have one-second resolution; the runs must not share one
expect "ls /var/log/tigris/*.jsonl >/dev/null 2>&1" "the run wrote its JSON report"
expect "! grep -qi 'not found' $W/run1.out" "no helper is missing from the run"

tigris --since last --root "$W/root" >"$W/run2.out" 2>&1; st=$?
expect "[ $st -eq 0 ]" "a --since run finishes clean (as root, nothing new)"
expect "grep -q 'Tigris diff:' $W/run2.out" "the --since run compared with the earlier one"

cd /tmp || exit 1
tigris-diff >"$W/diff.out" 2>&1; st=$?
expect "[ $st -eq 0 ]" "tigris-diff reads the package log directory by default"
tigris-export -f csv >"$W/export.csv" 2>"$W/export.err"; st=$?
expect "[ $st -eq 0 ] && head -1 $W/export.csv | grep -q '^host,run,time,level,id,'" "tigris-export converts the run to CSV"
tigris-export -f sarif >"$W/export.sarif" 2>>"$W/export.err"; st=$?
expect "[ $st -eq 0 ] && grep -q '\"version\":\"2.1.0\"' $W/export.sarif && [ ! -s $W/export.err ]" "and to SARIF, with the metadata found"

cd / || exit 1
tigris-accept -l >"$W/accept.out" 2>&1
expect "grep -q '/etc/tigris/tigris.accepted' $W/accept.out" "tigris-accept names the package accepted file"

[ "$fail" -eq 0 ] && echo PASS
exit $fail
