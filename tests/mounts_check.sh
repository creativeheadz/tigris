#!/bin/sh
#
# tests/mounts_check.sh - a filesystem that does not answer is left alone
#
# A hard NFS or CIFS mount whose server is down blocks every program that
# touches it. Feeds gen_mounts a mount table and a probe that hangs on one
# mount point, and checks that the scan list leaves that mount and the
# network filesystems out, says so, and does not wait for it. Then runs
# check_accounts and check_path (every user, Tigris_Check_PATHALL=Y) over a
# passwd file with one home on the hanging mount and checks that only that
# account is skipped, with a message. Then runs the file system scan over
# mount points whose names eval would misread. Needs no root and touches
# nothing outside a temporary directory.
#
# Exit 0 when every assertion holds, 1 otherwise.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write

TIMEOUT=`command -v timeout`
[ -n "$TIMEOUT" ] || { echo "skip: no timeout command, so no probe"; exit 0; }

W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log" "$W/fx"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# A mount table: local, pseudo, network, unknown, and one that will hang
cat > "$W/fx/mount" <<'FX'
#!/bin/sh
cat <<'TABLE'
/dev/sda1 on / type ext4 (rw,relatime)
proc on /proc type proc (rw,nosuid,nodev,noexec)
tmpfs on /run type tmpfs (rw,nosuid,nodev)
nas:/export on /mnt/nas type nfs4 (rw,hard)
//srv/share on /mnt/share type cifs (rw)
/dev/sdb1 on /mnt/slow type ext4 (rw,relatime)
weird on /mnt/weird type weirdfs (rw)
TABLE
FX
# The probe stands in for df -P PATH, and never answers under /mnt/slow
cat > "$W/fx/probe" <<'FX'
#!/bin/sh
case "$2" in /mnt/slow|/mnt/slow/*) sleep 60 ;; esac
exit 0
FX
chmod +x "$W/fx/mount" "$W/fx/probe"

# 1. gen_mounts, as the filesystem scan calls it
start=`date +%s`
GETFS="$W/fx/mount" TIMEOUT="$TIMEOUT" DF=/bin/df \
  Tigris_Mount_Probe_Cmd="$W/fx/probe" Tigris_Mount_Timeout=1 Tigris_FSScan_WarnUnknown=Y \
  sh "$W/systems/Linux/2/gen_mounts" local all > "$W/mounts.out" 2> "$W/mounts.err"
took=`expr \`date +%s\` - $start`

grep -q '^/ ext4 ' "$W/mounts.out"       && ok "root filesystem is scanned"        || bad "root filesystem missing from the scan list"
grep -q '^/run tmpfs ' "$W/mounts.out"   && ok "tmpfs is scanned"                  || bad "tmpfs missing from the scan list"
grep -q '/mnt/nas' "$W/mounts.out"       && bad "nfs4 mount in the scan list"       || ok "nfs4 mount left out"
grep -q '/mnt/share' "$W/mounts.out"     && bad "cifs mount in the scan list"       || ok "cifs mount left out"
grep -q '/mnt/slow' "$W/mounts.out"      && bad "hanging mount in the scan list"    || ok "hanging mount left out"
grep -q 'con011c.*/mnt/slow' "$W/mounts.err" && ok "con011c names the hanging mount" || bad "no con011c for the hanging mount"
grep -q 'con010c.*weirdfs' "$W/mounts.err"   && ok "con010c for the unknown type"    || bad "no con010c for weirdfs"
[ "$took" -lt 15 ] && ok "gen_mounts took ${took}s, did not wait for it" || bad "gen_mounts took ${took}s"

# 2. check_accounts and check_path over two users, one home on the hanging mount
mkdir -p "$W/fx/home/bob"
printf 'PATH=/usr/bin:/bin\nexport PATH\n' > "$W/fx/home/bob/.profile"
cat > "$W/fx/passwd" <<FX
alice:x:1001:1001:Alice:/mnt/slow/alice:/bin/sh
bob:x:1002:1002:Bob:$W/fx/home/bob:/bin/sh
FX
echo "the test's passwd file" > "$W/fx/passwd.src"
echo "$W/fx/passwd" > "$W/fx/pass.list"
cat >> "$W/tigris.conf" <<FX
Tigris_PasswdFiles='$W/fx/pass.list'
Tigris_Mount_Probe_Cmd='$W/fx/probe'
Tigris_Mount_Timeout=1
Tigris_Check_PATHALL=Y
FX

for check in check_accounts check_path
do
  start=`date +%s`
  ( cd "$W" && TIGERHOMEDIR=$W sh "scripts/$check" > "$W/$check.out" 2>&1 )
  took=`expr \`date +%s\` - $start`
  case $check in check_accounts) code=acc025w ;; check_path) code=path010w ;; esac
  grep -q "$code.*alice" "$W/$check.out" && ok "$check: $code for alice"   || { bad "$check: no $code for alice"; sed 's/^/     /' "$W/$check.out"; }
  grep -q "$code.*bob"   "$W/$check.out" && bad "$check: $code for bob too" || ok "$check: bob was checked"
  [ "$took" -lt 15 ] && ok "$check took ${took}s" || bad "$check took ${took}s"
done

# 3. The file system scan takes the mount points as data: whoever mounted
# a filesystem named its mount point (any user can, with FUSE). Two whose
# names eval would misread, each holding a directory named "...": a quote
# (a syntax error, so that mount went unscanned) and $HOME (expanded to
# another path). Both are scanned as named (fsys005a for each "...").
# (GNU find only: busybox's has no -fprintf, and its slower path does
# not report these names at all, a separate gap)
if find / -maxdepth 0 -printf '' >/dev/null 2>&1; then
mkdir -p "$W/fx/it's/..." "$W/fx/cost\$HOME/..."
{
  echo '#!/bin/sh'
  echo "cat <<'TABLE'"
  printf '/dev/sdy1 on %s type ext4 (rw,relatime)\n' "$W/fx/it's" "$W/fx/cost\$HOME"
  echo TABLE
} > "$W/fx/mount2"
chmod +x "$W/fx/mount2"
cp "$W/tigris.conf" "$W/tigris.conf.scan"
cat >> "$W/tigris.conf" <<FX
Tigris_Mounts_Cmd='$W/fx/mount2'
Tigris_FSScan_ofNote=Y
Tigris_FSScan_DetailDirs='*'
Tigris_FSScan_PruneDirs=''
FX
# (_TIGER_RUN as tiger sets it: else each sub/ check's cleanup deletes the
# others' messages)
( cd "$W" && _TIGER_RUN=Y TIGERHOMEDIR=$W sh scripts/find_files ) > "$W/scan.out" 2>&1
grep -qF "$W/fx/it's/..." "$W/scan.out" &&
  ok "a mount point with a quote in its name is scanned" || { bad "the quoted mount point was not scanned"; sed 's/^/     /' "$W/scan.out"; }
grep -qF "$W/fx/cost\$HOME/..." "$W/scan.out" &&
  ok "a mount point with \$HOME in its name is scanned as named" || { bad "the \$HOME mount point was not scanned"; sed 's/^/     /' "$W/scan.out"; }
cp "$W/tigris.conf.scan" "$W/tigris.conf"
else
  echo "ok   (no GNU find here: the scan of odd mount point names is not tested)"
fi

[ $fail -eq 0 ] && echo "mounts_check: all assertions hold" || echo "mounts_check: FAILED"
exit $fail
