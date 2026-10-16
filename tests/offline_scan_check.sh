#!/bin/sh
#
# tests/offline_scan_check.sh - the file system scan of an offline root
#
# Runs tigris --root with the scan on (setuid, setgid, world-writable
# directories, unowned files, links, odd names, devices) over a root that
# holds one of each: a setuid program no package ships, a setgid script,
# world-writable directories (one not sticky, reported; one sticky as /tmp
# is, not reported; one sticky under /etc, reported), world-writable files
# (one under /etc, listed; two in a home directory, counted), a directory named
# "...", an absolute link to a
# file this host has and the root does not (dangling inside the root; it
# must not be followed to this host's file), and one to a file the root
# has (not dangling). The root's passwd knows the files' uid but its group
# file does not know their gid, though this host does: every file must
# then be one "without a defined group", which only the root's group file
# can say. Every finding must name the root's paths. As root a device file
# outside /dev is added. Needs GNU find.
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
U=$uid; G=`id -g`
[ "$uid" = 0 ] && { U=4242; G=4243; }
find / -maxdepth 0 -printf '' 2>/dev/null || { echo "ok   (no GNU find here: nothing to test)"; echo PASS; exit 0; }

R=$W/img
mkdir -p "$R/etc" "$R/usr/bin" "$R/srv/drop" "$R/srv/shared" "$R/etc/zz-drop" "$R/opt/..." "$R/dev" "$R/home/milo"
printf 'root:x:0:0:root:/root:/bin/sh\nmilo:x:%s:%s:Milo:/home/milo:/bin/sh\n' "$U" "$G" > "$R/etc/passwd"
printf 'root:x:0:\n' > "$R/etc/group"
printf '\177ELF' > "$R/usr/bin/zz-suid"; chmod 4755 "$R/usr/bin/zz-suid"
printf '#!/bin/sh\necho hi\n' > "$R/usr/bin/zz-sgid-script"; chmod 2755 "$R/usr/bin/zz-sgid-script"
chmod 777 "$R/srv/drop"; chmod 1777 "$R/srv/shared" "$R/etc/zz-drop"
: > "$R/etc/zz-open"; : > "$R/home/milo/zz-a"; : > "$R/home/milo/zz-b"
chmod 666 "$R/etc/zz-open" "$R/home/milo/zz-a" "$R/home/milo/zz-b"
ln -s /etc/hostname "$R/etc/zz-hostlink"
ln -s /etc/passwd "$R/etc/zz-ok"
[ -e /etc/hostname ] || : > "$W/hostname-missing"
if [ "$uid" = 0 ]; then
  mknod "$R/opt/zz-dev" c 1 3
  chown -R "$U:$G" "$R"
  chown -h "$U:$G" "$R/etc/zz-hostlink" "$R/etc/zz-ok"
  # chown clears the setuid and setgid bits
  chmod 4755 "$R/usr/bin/zz-suid"; chmod 2755 "$R/usr/bin/zz-sgid-script"
fi

{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  echo 'Tigris_Deb_CheckMD5Sums=N'; echo 'Tigris_Deb_NoPackFiles=N'; echo 'Tigris_Deb_StatOverride=N'
  echo 'Tigris_Check_FILESYSTEM=Y'
  for s in Setuid Setgid Devs SymLinks ofNote WDIR WFILE Unowned; do echo "Tigris_FSScan_$s=Y"; done
  echo "Tigris_FSScan_PruneDirs=''"
} > "$W/profiles/scan"
chmod 644 "$W/profiles/scan"

( cd "$W" && sh ./tigris -q --profile scan --root "$R" ) > "$W/out" 2>&1
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
[ -n "$report" ] || { echo "FAIL no report:"; cat "$W/out"; exit 1; }
has() { grep -F -q -- "$1" "$report"; }

has '[fsys004a] Setuid program /usr/bin/zz-suid (-rwsr-xr-x, owner' &&
  ok "a setuid program no package ships, by the root's path: fsys004a" || bad "fsys004a"
has '[fsys010w] File /usr/bin/zz-sgid-script is a setgid script' && ok "a setgid script: fsys010w" || bad "fsys010w"
has '[fsys008f] Directory /srv/drop is world writable (drwxrwxrwx' && has 'Not sticky' &&
  ok "a world-writable directory: fsys008f" || bad "fsys008f"
# (as a finding of its own, or a line of the list fsys008f printed until
# October 2026, which ended in a slash)
{ has 'Directory /srv/shared ' || grep -qx '/srv/shared/' "$report"; } &&
  bad "a sticky world-writable directory, shared as /tmp is, was reported" ||
  ok "a sticky one, shared as /tmp is: no finding"
has '[fsys008f] Directory /etc/zz-drop is world writable (drwxrwxrwt' && has 'Sticky, but under /etc' &&
  ok "a sticky one under /etc, where root reads configuration: fsys008f" || bad "sticky under /etc"
has '[fsys020f] File /etc/zz-open is world writable (-rw-rw-rw-, owner' && has 'Under /etc, where root reads programs and configuration' &&
  ok "a world-writable file under /etc, listed with its mode and owner: fsys020f" || bad "fsys020f"
# (the text report wraps at 79 columns: match what fits on the first line)
has '[fsys021w] 2 world-writable files under /home/milo' && ! has 'File /home/milo/zz-a ' &&
  ok "two in a home directory: counted, not listed: fsys021w" || bad "fsys021w"
has "Unusual filename \`...' found" && ok "a directory named ...: fsys005a" || bad "fsys005a"
has '[fsys013w] /etc/zz-hostlink is a dangling symlink' &&
  ok "an absolute link to a file this host has and the root does not: dangling inside the root" || bad "dangling"
has '/etc/zz-ok is a dangling' && bad "a link to a file the root has was called dangling" || ok "a link to a file the root has is not dangling"
has 'do not have an defined groups' && has '/usr/bin/zz-suid' &&
  ok "files whose gid the root's group file does not know (this host's does): fsys015w" || bad "fsys015w"
has 'The following files are unowned' && bad "files whose uid the root's passwd knows were called unowned" || ok "the root's passwd knows their uid: no fsys014w"
if [ "$uid" = 0 ]; then
  has 'Unexpected device files found' && has '/opt/zz-dev' && ok "a device outside /dev: fsys006a" || bad "fsys006a"
fi
grep -q "$R" "$report" | grep -v 'Auditing the system in' && bad "a finding names where the root is on this host" || true
sed -n '/^--/,$p' "$report" | grep -q "$R" && bad "the report names where the root is on this host" ||
  ok "every finding names the root's own paths"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- report"; cat "$report"; }
exit $fail
