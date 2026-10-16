#!/bin/sh
#
# tests/suid_check.sh - check_suid and check_sgid against the package database
#
# Runs the two sub-checks as the filesystem scan does (config sourced, a
# list of files in), with LXPKGMGR set to apk (an installed database under
# Tigris_Sysctl_Root), rpm (a stand-in for rpm -qa's modes through
# Tigris_Rpm_Modes_Cmd) and dpkg (file lists and statoverrides under
# Tigris_Sysctl_Root, and Tigris's list of what Debian and Ubuntu packages
# make setuid, DPKG_SPECIAL; Tigris's per-platform list without it). Of
# the setuid files, those a package makes setuid are expected and the
# others are non-standard, one finding each. util/pkgspecial itself was
# compared with find -perm in Fedora, Arch and Alpine containers on 7
# October 2026, and its dpkg side on a Linux Mint desktop and 42 Ubuntu
# and Debian servers on 12 October 2026, and agreed.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/fs" "$W/root/lib/apk/db" "$W/root/var/lib/dpkg/info"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

P=$W/fs/packaged L=$W/fs/local O=$W/fs/overridden V=$W/fs/vendor
for f in "$P" "$L" "$O" "$V"; do printf '\177ELF' > "$f"; chmod 755 "$f"; done
printf '%s\n%s\n' "$L" "$P" | sort > "$W/setuid.in"
printf '%s\n%s\n%s\n%s\n' "$L" "$P" "$O" "$V" | sort > "$W/setuid4.in"
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
# dpkg: demo ships P, which the list says it makes setuid; vendor ships V,
# a package the list does not know; an override makes O setuid; nothing
# installed L
printf '/.\n%s\n' "$P" > "$W/root/var/lib/dpkg/info/demo.list"
printf '%s\n' "$V" > "$W/root/var/lib/dpkg/info/vendor.list"
printf 'root root 4755 %s\nroot root 0755 %s\n' "$O" "$L" > "$W/root/var/lib/dpkg/statoverride"
printf '# mode package path\n4755 demo %s\n4755 absent %s\n' "$P" "$L" > "$W/dpkg_special"

cat > "$W/drive.sh" <<'EOF'
basedir=$TIGERHOMEDIR
. $basedir/config
# tigris.conf sets Tigris_Sysctl_Root empty: the tree is given after it
LXPKGMGR=$MGR SUID_LIST=$LIST SGID_LIST=$LIST CONFIGURED_ALREADY=YES Tigris_Sysctl_Root=$ROOT
DPKG_SPECIAL=$SPECIAL Tigris_Output_Width=0
export LXPKGMGR SUID_LIST SGID_LIST CONFIGURED_ALREADY Tigris_Sysctl_Root DPKG_SPECIAL Tigris_Output_Width
sh $BASEDIR/scripts/sub/check_$KIND $INPUT
EOF
go() {  # go MANAGER KIND [INPUT] [SPECIAL]
  ( cd "$W" && TIGERHOMEDIR=$W MGR=$1 KIND=$2 INPUT="${3:-$W/setuid.in}" LIST="$W/suid_list" \
      SPECIAL="$4" ROOT="$W/root" Tigris_Rpm_Modes_Cmd="sh $W/rpm" sh ./drive.sh ) > "$W/out" 2>&1
  # the file each fsys004a or fsys011a names (one finding a file)
  sed -n -E 's/^--ALERT-- \[fsys0(04a|11a)\] Set[gu]id program (.*) \([^()]*\) is non-standard\.$/\2/p' "$W/out" > "$W/listed"
}
listed() { grep -qx "$1" "$W/listed"; }

go apk suid
grep -q 'fsys004a' "$W/out" && listed "$L" && ! listed "$P" && grep -q "No installed package makes it setuid (apk's database)" "$W/out" &&
  ok "apk: the file the package ships setuid is expected, the other is fsys004a" || { bad "apk suid"; cat "$W/out"; }
grep -q "Setuid program $L (-rwxr-xr-x, owner [^ ]*) is non-standard" "$W/out" &&
  ok "the finding gives the file's mode and owner" || { bad "mode and owner"; cat "$W/out"; }
go rpm suid
listed "$L" && ! listed "$P" && grep -q "(rpm's database)" "$W/out" &&
  ok "rpm: from its file modes, the same" || { bad "rpm suid"; cat "$W/out"; }
go apk sgid
grep -q 'fsys011a' "$W/out" && listed "$L" && listed "$P" && [ "`wc -l < "$W/listed"`" -eq 2 ] &&
  ok "apk, setgid: neither is setgid in the package (only 'other' is): one fsys011a each" || { bad "apk sgid"; cat "$W/out"; }
go dpkg suid "$W/setuid.in" ""
listed "$L" && ! listed "$P" && grep -q "Not in Tigris's list of the setuid programs" "$W/out" &&
  ok "dpkg without Tigris's Debian list: the platform's list, as before" || { bad "dpkg, static list"; cat "$W/out"; }

go dpkg suid "$W/setuid4.in" "$W/dpkg_special"
! listed "$P" && ok "dpkg: a file the list says its installed package makes setuid is expected" || { bad "dpkg packaged"; cat "$W/out"; }
! listed "$O" && ok "dpkg: a file dpkg-statoverride makes setuid is expected" || { bad "dpkg statoverride"; cat "$W/out"; }
listed "$L" && grep -q "$L (.*is non-standard\.$" "$W/out" && grep -A1 "Setuid program $L " "$W/out" | grep -q 'No package installed it\.' &&
  ok "dpkg: a file the list names for a package not installed, that no package installed, is fsys004a, and said" || { bad "dpkg local"; cat "$W/out"; }
listed "$V" && grep -A1 "Setuid program $V " "$W/out" | grep -q 'It is from package vendor\.' &&
  ok "dpkg: a file from a package the list does not know is fsys004a, its package named" || { bad "dpkg vendor"; cat "$W/out"; }
grep -q "Tigris's list of what Debian and Ubuntu packages make setuid" "$W/out" &&
  ok "dpkg: the detail says what was compared" || { bad "dpkg detail"; cat "$W/out"; }

# Relative pathnames (fsys002w) only in a program no package makes
# setuid: sudo, pkexec and ssh-keysign all name "../" to refuse it
if command -v strings >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
  for f in "$P" "$L"; do printf '\177ELF\0../lib/helper\0' > "$f"; done
  go dpkg suid "$W/setuid4.in" "$W/dpkg_special"
  grep -q "\[fsys002w\] setuid program $L has relative pathnames" "$W/out" &&
    ! grep -q "\[fsys002w\] setuid program $P " "$W/out" &&
    ok "relative pathnames: said of the non-standard program, not of the packaged one" || { bad "fsys002w"; cat "$W/out"; }
fi

# usrmerge and multiarch: a file list may name /bin/... for the
# /usr/bin/... the scan finds (where /bin is a link), and the list names
# one architecture's triplet for every architecture's
M=$W/merged
mkdir -p "$M/usr/bin" "$M/var/lib/dpkg/info"
ln -s usr/bin "$M/bin"
printf '/bin/zz-mount\n' > "$M/var/lib/dpkg/info/mount.list"
printf '/usr/lib/aarch64-linux-gnu/utempter/utempter\n' > "$M/var/lib/dpkg/info/libutempter0:arm64.list"
printf '/usr/bin/zz-other\n' > "$M/var/lib/dpkg/info/other.list"
printf '4755 mount /usr/bin/zz-mount\n2755 libutempter0 /usr/lib/x86_64-linux-gnu/utempter/utempter\n4755 mount /usr/bin/zz-other\n' > "$W/merged_special"
out=`LXPKGMGR=dpkg Tigris_Sysctl_Root=$M DPKG_SPECIAL=$W/merged_special sh "$W/util/pkgspecial" suid`
[ "$out" = /usr/bin/zz-mount ] &&
  ok "dpkg, usrmerge: the list's /usr/bin/zz-mount is the file list's /bin/zz-mount; another package's file is not" || bad "usrmerge: got '$out'"
out=`LXPKGMGR=dpkg Tigris_Sysctl_Root=$M DPKG_SPECIAL=$W/merged_special sh "$W/util/pkgspecial" sgid`
[ "$out" = /usr/lib/aarch64-linux-gnu/utempter/utempter ] &&
  ok "dpkg, multiarch: the list's x86_64 utempter is the arm64 package's" || bad "multiarch: got '$out'"
rm "$M/bin"; mkdir "$M/bin"
out=`LXPKGMGR=dpkg Tigris_Sysctl_Root=$M DPKG_SPECIAL=$W/merged_special sh "$W/util/pkgspecial" suid`
[ "$out" = /bin/zz-mount ] &&
  ok "dpkg, no usrmerge: /bin/zz-mount is itself, not /usr/bin/zz-mount" || bad "unmerged: got '$out'"
out=`printf '/bin/zz-mount\n/usr/bin/zz-nobody\n' | LXPKGMGR=dpkg Tigris_Sysctl_Root=$M WORKDIR=$W/run sh "$W/util/pkgspecial" owners`
[ "$out" = "/bin/zz-mount	mount" ] && ok "pkgspecial owners: a file's package, none for a file no package has" || bad "owners: got '$out'"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
