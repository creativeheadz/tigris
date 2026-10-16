#!/bin/sh
#
# tests/macos_dispatch_check.sh - the MacOSX tree resolves and runs
#
# Two proofs. First, run_script with OS=MacOSX finds the MacOSX
# check: check_sudo is a symlink to the Linux parser, and the
# emission still works. Second, that parser reads a macOS-shaped
# root: a NOPASSWD rule reports sudo001w through the symlink, so
# the shared grammar needs no Mac fork. Runs as a user and as
# root; the fixtures read the same for both.
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
# cvtsudoers ships with sudo, which a minimal image has not: read the
# flattened rules straight, as the Linux sudo suite's stubs stand in
echo "Tigris_Cvtsudoers_Cmd='cat'" >> "$W/tigris.conf"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

M=$W/macroot; mkdir -p "$M/etc"
cat > "$M/etc/sudoers" <<'EOF'
root ALL=(ALL) ALL
%admin ALL=(ALL) ALL
helpdesk ALL=(ALL) NOPASSWD: ALL
EOF
chmod 440 "$M/etc/sudoers"
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_sudo' ) 2>&1 |
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' | grep -v '^# Skipped' > "$W/out" || true
if [ "`id -u`" -eq 0 ]; then
  # no sudo boundary here: sudo would strip OS and TIGRIS_ROOT, so
  # this leg runs in the suite's own (root) shell, which CI reaches
  # through `sudo sh tests/macos_dispatch_check.sh`
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_sudo' ) 2>&1 |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out" || true
  grep -F -q -- '--WARN-- [sudo001w]' "$W/out" &&
  grep -F -q 'helpdesk' "$W/out" &&
    ok "dispatched check_sudo on a macOS root: sudo001w" || { bad "sudo-macroot"; cat "$W/out"; }
else
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_sudo' ) 2>&1 | grep -F -q 'Skipped check_sudo: it needs root' &&
    ok "dispatched check_sudo honors needs-root through the symlink" || bad "sudo-skip"
fi

# The whole chain, as tiger runs it: check_system finds the MacOSX
# aggregator, which runs the MacOSX checks
( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_system' ) 2>&1 |
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' | grep -v '^# Skipped' > "$W/chain" || true
if [ "`id -u`" -eq 0 ]; then
  grep -F -q -- '--WARN-- [sudo001w]' "$W/chain" &&
    ok "check_system chain on a macOS root: sudo001w" || { bad "chain-macroot"; cat "$W/chain"; }
else
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$M" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script check_system' ) 2>&1 |
    grep -F -q 'Skipped check_sudo: it needs root' &&
    ok "check_system chain as a user: aggregator runs, sudo skips" || bad "chain-user"
fi

# Precedence: where a portable check exists, the MacOSX shadow must
# win. One root carries a dslocal uid 0, a dup gid, a readable
# audit trail and a writable tab, but none of the Linux paths the
# portable checks read: any finding is the shadow's.
P=$W/precision; mkdir -p "$P/etc" \
  "$P/var/db/dslocal/nodes/Default/users" \
  "$P/var/db/dslocal/nodes/Default/groups" \
  "$P/var/audit" "$P/var/at/tabs"
cp "$TIGER/tests/fixtures/macos/dsusers/evil.plist" "$P/var/db/dslocal/nodes/Default/users/"
cp "$TIGER/tests/fixtures/macos/dsgroups/dup1.plist" "$TIGER/tests/fixtures/macos/dsgroups/dup2.plist" "$P/var/db/dslocal/nodes/Default/groups/"
touch "$P/var/audit/trail"; chmod 644 "$P/var/audit/trail"
printf '0 9 * * * /usr/local/bin/good\n' > "$P/var/at/tabs/helen"; chmod 666 "$P/var/at/tabs/helen"
for c in "check_passwd:pass017w" "check_group:grp001w" "check_logfiles:logf009w" "check_crontabs:cron008f"
do
  name=${c%%:*}; want=${c#*:}
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$P" OS=MacOSX sh -c '. ./config >/dev/null 2>&1; . $BASEDIR/initdefs; run_script '"$name" ) 2>&1 |
  grep -F -q -- "[$want]" && ok "run_script $name resolves to the MacOSX shadow" || bad "precedence-$name"
done

[ $fail -eq 0 ] && echo "PASS"
exit $fail
