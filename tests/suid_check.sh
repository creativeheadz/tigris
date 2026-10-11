#!/bin/sh
#
# tests/suid_check.sh - check_suid and check_sgid against the package database
#
# Runs the two sub-checks as the filesystem scan does (config sourced, a
# list of files in), with LXPKGMGR set to apk (an installed database under
# Tiger_Sysctl_Root), rpm (a stand-in for rpm -qa's modes through
# Tiger_Rpm_Modes_Cmd) and dpkg (no modes, so Tigris's own list). Of two
# setuid files, the package ships one setuid: only the other is
# non-standard. util/pkgspecial itself was compared with find -perm in
# Fedora, Arch and Alpine containers on 7 October 2026 and agreed.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/fs" "$W/root/lib/apk/db"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

P=$W/fs/packaged L=$W/fs/local
for f in "$P" "$L"; do printf '\177ELF' > "$f"; chmod 755 "$f"; done
printf '%s\n%s\n' "$L" "$P" | sort > "$W/setuid.in"
d=${W#/}/fs
cat > "$W/root/lib/apk/db/installed" <<EOF
P:demo
V:1.0
F:$d
R:packaged
a:0:0:4755
Z:Q1aaaa=
R:other
a:0:0:2755
EOF
printf '#!/bin/sh\necho "104755 %s"\necho "100755 %s"\n' "$P" "$L" > "$W/rpm"
echo "$P" > "$W/suid_list"

cat > "$W/drive.sh" <<'EOF'
basedir=$TIGERHOMEDIR
. $basedir/config
# tigerrc sets Tiger_Sysctl_Root empty: the tree is given after it
LXPKGMGR=$MGR SUID_LIST=$LIST SGID_LIST=$LIST CONFIGURED_ALREADY=YES Tiger_Sysctl_Root=$ROOT
export LXPKGMGR SUID_LIST SGID_LIST CONFIGURED_ALREADY Tiger_Sysctl_Root
sh $BASEDIR/scripts/sub/check_$KIND $INPUT
EOF
go() {  # go MANAGER KIND
  ( cd "$W" && TIGERHOMEDIR=$W MGR=$1 KIND=$2 INPUT="$W/setuid.in" LIST="$W/suid_list" \
      ROOT="$W/root" Tiger_Rpm_Modes_Cmd="sh $W/rpm" sh ./drive.sh ) > "$W/out" 2>&1
  # the files fsys004a or fsys011a lists come after it, one per line
  awk '/fsys0(04a|11a)/ { on = 1; next } on && /^ *[-a-z]/ { print $NF } /^$/ { on = 0 }' "$W/out" > "$W/listed"
}
listed() { grep -qx "$1" "$W/listed"; }

go apk suid
grep -q 'fsys004a' "$W/out" && listed "$L" && ! listed "$P" && grep -q "Not setuid in any installed package (apk's database)" "$W/out" &&
  ok "apk: the file the package ships setuid is expected, the other is fsys004a" || { bad "apk suid"; cat "$W/out"; }
go rpm suid
listed "$L" && ! listed "$P" && grep -q "(rpm's database)" "$W/out" &&
  ok "rpm: from its file modes, the same" || { bad "rpm suid"; cat "$W/out"; }
go apk sgid
grep -q 'fsys011a' "$W/out" && listed "$L" && listed "$P" &&
  ok "apk, setgid: neither is setgid in the package (only 'other' is): both fsys011a" || { bad "apk sgid"; cat "$W/out"; }
go dpkg suid
listed "$L" && ! listed "$P" && grep -q "Not in Tigris's list of the setuid programs" "$W/out" &&
  ok "dpkg, which records no modes: Tigris's list, as before" || { bad "dpkg"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
