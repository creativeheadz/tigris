#!/bin/sh
#
# tests/install_check.sh - the installed tree runs, from sbin to the last helper
#
# Copies this tree aside (so the build dirties no checkout), configures,
# makes and installs it under a throwaway prefix, then runs the installed
# sbin/tigris twice against a tiny offline root: once with -E (which
# needs $BASEDIR/tigexp) and once with --since last (which needs
# $BASEDIR/tigris-diff). Installing the entry points without the helpers
# they call is the failure; sbin/tigris explain (which needs tigexp
# beside it) is checked too.
#
# Needs a C compiler and make; exits 2 (skip) without them.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write

command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || { echo "SKIP: a C compiler is needed"; exit 2; }
command -v make >/dev/null 2>&1 || { echo "SKIP: make is needed"; exit 2; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
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

( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( mkdir "$W/src" && cd "$W/src" && tar -xf - )
cd "$W/src" || exit 1
# A real install under a throwaway prefix (a DESTDIR staging directory
# bakes paths that only exist once unpacked, so it cannot run in place)
./configure --prefix="$W/pfx" --localstatedir="$W/pfx/var" >"$W/configure.log" 2>&1
expect "[ $? -eq 0 ]" "configure runs"
make >"$W/make.log" 2>&1
expect "[ $? -eq 0 ]" "make builds the helpers and the docs"
make install >"$W/install.log" 2>&1
expect "[ $? -eq 0 ]" "make install fills the prefix"
[ "$fail" -ne 0 ] && { tail -5 "$W/configure.log" "$W/make.log" "$W/install.log" 2>/dev/null; exit 1; }

SBIN="$W/pfx/sbin"
STAGEHOME=`grep '^TIGERHOME=' "$W/src/Makefile" | sed 's/.*=//'`
expect "[ -x $SBIN/tigris ]" "sbin/tigris is installed and executable"
expect "[ -x $STAGEHOME/tigexp ]" "tigexp is where BASEDIR expects it"
# what was copied from the checkout keeps nobody's write bit (the checkout's
# modes are the cloner's umask); as root, all of it is root's
expect "[ -z \"`find $STAGEHOME ! -type l -perm /go+w 2>/dev/null | head -1`\" ]" "nothing installed is writable by group or others"
[ "`id -u`" = 0 ] && expect "[ -z \"`find $STAGEHOME ! -user root 2>/dev/null | head -1`\" ]" "installed as root: everything is root's"
expect "[ -x $STAGEHOME/tigris-diff ]" "tigris-diff is where BASEDIR expects it"

$SBIN/tigris explain lin002i >"$W/explain.out" 2>&1
expect "grep -q 'Severity:' $W/explain.out" "sbin/tigris explain finds tigexp"

# version.h is installed: a package once said "version undetermined"
ver=`cat "$W/src/version.h"`
$SBIN/tigris -v >"$W/v.out" 2>&1
expect "grep -qF \"Tigris, version \$ver\" $W/v.out" "the installed tigris knows its version"

mkdir -p "$W/root/etc" "$W/root/bin"
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$W/root/etc/passwd"
printf 'root:x:0:\n' > "$W/root/etc/group"
printf '#!/bin/sh\necho hi\n' > "$W/root/bin/hi"
chmod 755 "$W/root/bin/hi"

$SBIN/tigris -q -E --root "$W/root" >"$W/run1.out" 2>&1; st=$?
case $st in 0|3|4|5) expect true "the installed tree finishes a run with -E";; *) expect false "the installed tree finishes a run with -E (exit $st)";; esac
sleep 2 # report names have one-second resolution; the runs must not share one
LOG=`grep '^TIGERLOGS=' "$W/src/Makefile" | sed 's/.*=//'`
expect "ls $LOG/*.jsonl >/dev/null 2>&1" "the run wrote its JSON report"
expect "! grep -qi 'not found' $W/run1.out" "no helper is missing from the run"

# Not quiet: with -q, an unchanged --since prints nothing. Exit 2 is the
# documented status for this run (as a user, checks are skipped for want
# of root, and nothing new was found).
$SBIN/tigris --since last --root "$W/root" >"$W/run2.out" 2>&1; st=$?
# (as root nothing is skipped, so the status is whatever the root's findings
# say, 0 to 5; as a user it is 2)
if [ "`id -u`" = 0 ]; then expect "[ $st -ge 0 ] && [ $st -le 5 ]" "the installed tree finishes a run with --since (as root: exit $st)"
else expect "[ $st -eq 2 ]" "the installed tree finishes a run with --since"; fi
expect "grep -q 'Tigris diff:' $W/run2.out" "the --since run compared with the earlier one"

[ "$fail" -eq 0 ] && echo PASS
exit $fail
