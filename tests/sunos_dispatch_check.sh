#!/bin/sh
#
# tests/sunos_dispatch_check.sh - the SunOS tree resolves and runs
#
# Two proofs. First, the whole chain as tiger runs it: check_system
# finds the SunOS aggregator, and a root with no audit_control gets
# exactly aud001w (the live-only checks stay silent offline, the
# shadows find no files). Second, precedence: where a portable
# check exists, the SunOS shadow wins, so a dslocal-free root with
# a second uid 0 reports pass017w from the shadow. Runs as a user
# and as root; the fixtures read the same for both.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
# run_script runs nothing owned by another user: as root the copied
# tree must be root's, as in the offline and cron suites
[ "`id -u`" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
join() {  # join: logical lines (continuations start with a space)
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' | grep -v '^# Skipped'
}

M=$W/sunosroot; mkdir -p "$M/etc"
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=SunOS sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_system' ) 2>&1 |
join > "$W/chain" || true
grep -F -q -- '--WARN-- [aud001w]' "$W/chain" &&
[ "`grep -c '^--' "$W/chain"`" = 1 ] &&
  ok "check_system chain on a SunOS root: exactly aud001w" || { bad "chain"; cat "$W/chain"; }

P=$W/precision; mkdir -p "$P/etc"
cat > "$P/etc/passwd" <<'EOF'
root:x:0:0:Super-User:/root:/bin/bash
evil:x:0:0::/:/bin/bash
EOF
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$P" OS=SunOS sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_passwd' ) 2>&1 |
join > "$W/out" || true
grep -F -q -- '[pass017w]' "$W/out" &&
grep -F -q 'evil' "$W/out" &&
  ok "run_script check_passwd resolves to the SunOS shadow" || { bad "precedence-check_passwd"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
