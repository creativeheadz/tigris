#!/bin/sh
#
# tests/portable_bsd_check.sh - the portable checks, and tiger itself, on FreeBSD
#
# Until October 2026 the FreeBSD config defined none of what tiger and
# the portable checks need: tiger stopped at init001e before running a
# check, and so did check_passwd, check_group, check_accounts,
# check_crontabs, check_umask and check_perms. Here each runs with the
# FreeBSD config (OS=FreeBSD) on FreeBSD-shaped roots: the accounts in
# master.passwd (ten fields), crontabs in /var/cron/tabs, cron.d in
# /usr/local/etc, periodic scripts, login.conf's umask, the permission
# database's wheel group. A clean root stays quiet, a loose one is
# reported, nothing stops at init001e, and check_issue says it does not
# apply. Last, a whole tigris --root run. Runs as a user and as root.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
uid=`id -u`; gid=`id -g`
[ "$uid" = 0 ] && chown -R 0:0 "$W"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# run CHECK ROOT: the portable CHECK with the FreeBSD config, ROOT the
# audited system, its findings one a line in $W/out
run() {
  ( cd "$W" && OS=FreeBSD REV=14.1-RELEASE ARCH=amd64 TIGERHOMEDIR=$W TIGRIS_ROOT="$2" sh "./scripts/$1" ) > "$W/raw" 2>&1
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' "$W/raw" |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }
noerr() { ! grep -q 'ERROR\|init00\|not found' "$W/raw"; }
H6='$6$Ab1Cd2Ef$8vXQhJf0rZpN0cB7yWl3m1qKx9tE4uR5sD6aF7gH8jK9lZ0xC1vB2nM3qW4eR5tY6uI7oP8aS9dF0gH1jK2lZ'

# root ROOT: a FreeBSD root as installed, owned (when the test is root)
# by root and wheel; as a user the files are the user's, so the
# permission database's owner is named in the root's passwd as that uid
root() {
  r=$1; mkdir -p "$r/etc/periodic/daily" "$r/usr/local/etc/cron.d" "$r/var/cron/tabs" "$r/home/alice" "$r/root" "$r/bin" "$r/usr/sbin" "$r/var/at"
  cat > "$r/etc/master.passwd" <<EOF
# \$FreeBSD\$
root:$H6:0:0::0:0:Charlie &:/root:/bin/sh
daemon:*:1:1::0:0:Owner of many system processes:/root:/usr/sbin/nologin
operator:*:2:5::0:0:System &:/:/usr/sbin/nologin
nobody:*:65534:65534::0:0:Unprivileged user:/nonexistent:/usr/sbin/nologin
alice:$H6:1001:1001::0:0:Alice:/home/alice:/bin/sh
EOF
  awk -F: '/^#/ { print; next } { print $1 ":*:" $3 ":" $4 ":" $8 ":" $9 ":" $10 }' "$r/etc/master.passwd" > "$r/etc/passwd"
  printf '# $FreeBSD$\nwheel:*:0:root\ndaemon:*:1:\noperator:*:5:root\nnobody:*:65534:\nalice:*:1001:\n' > "$r/etc/group"
  printf '# shells\n/bin/sh\n/bin/csh\n/bin/tcsh\n' > "$r/etc/shells"
  printf '#!/bin/sh\n' > "$r/bin/sh"; chmod 555 "$r/bin/sh"
  printf '# shrc\n' > "$r/home/alice/.shrc"; printf '# profile\n' > "$r/home/alice/.profile"
  chmod 750 "$r/home/alice"
  cat > "$r/etc/crontab" <<'EOF'
SHELL=/bin/sh
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin
#minute	hour	mday	month	wday	who	command
*/11	*	*	*	*	operator /usr/libexec/save-entropy
1	3	*	*	*	root	/usr/sbin/periodic daily
EOF
  printf '#!/bin/sh\n' > "$r/etc/periodic/daily/100.clean-disks"; chmod 555 "$r/etc/periodic/daily/100.clean-disks"
  printf '0 2 * * * root /usr/local/bin/backup\n' > "$r/usr/local/etc/cron.d/backup"
  printf '0 * * * * /home/alice/bin/sync\n' > "$r/var/cron/tabs/alice"; chmod 600 "$r/var/cron/tabs/alice"
  chmod 700 "$r/var/cron/tabs"
  : > "$r/var/cron/deny"
  : > "$r/var/at/at.deny"
  printf '# shrc\n' > "$r/root/.shrc"
  cat > "$r/etc/login.conf" <<'EOF'
# login.conf
default:\
	:passwd_format=sha512:\
	:path=/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin ~/bin:\
	:copyright=/etc/COPYRIGHT:\
	:umask=022:

russian|Russian Users Accounts:\
	:umask=000:\
	:tc=default:
EOF
  printf '# System-wide .profile file for sh(1).\n' > "$r/etc/profile"
  printf '# System-wide .login file for csh(1).\n' > "$r/etc/csh.login"
  printf 'sshd_enable="YES"\n' > "$r/etc/rc.conf"
  chmod 600 "$r/etc/master.passwd"
  if [ "$uid" = 0 ]; then
    chown -R 0:0 "$r"; chown -R 1001:1001 "$r/home/alice"
  else
    # the runner's uid and gid are the root's root and wheel, for the
    # owners check_perms names
    sed -i "s/^root:\([^:]*\):0:0:/root:\1:$uid:$gid:/" "$r/etc/master.passwd" "$r/etc/passwd"
    sed -i "s/^wheel:\*:0:/wheel:*:$gid:/" "$r/etc/group"
  fi
}

C=$W/clean; root "$C"
L=$W/loose; root "$L"
# loose: toor (a second uid 0, its shell empty), a locked account with a
# shell, a weak hash, a duplicate group, a world-writable home, a
# crontab anyone may write and one for no account, a relative command,
# login.conf's default umask letting others write, the master file and
# rc.conf open
cat >> "$L/etc/master.passwd" <<EOF
toor:*:0:0::0:0:Bourne-again Superuser:/root:
bob:*LOCKED*$H6:1002:1002::0:0:Bob:/home/bob:/bin/sh
eve:_J9..abcdefghijklmno:1003:1003::0:0:Eve:/home/eve:/bin/sh
EOF
awk -F: '$1 == "toor" || $1 == "bob" || $1 == "eve" { print $1 ":*:" $3 ":" $4 ":" $8 ":" $9 ":" $10 }' "$L/etc/master.passwd" >> "$L/etc/passwd"
for u in bob eve; do mkdir -p "$L/home/$u"; printf '# shrc\n' > "$L/home/$u/.shrc"; done
printf 'wheel:*:%s:root\n' "`awk -F: '$1 == "wheel" { print $3 }' "$L/etc/group"`" >> "$L/etc/group"
chmod 777 "$L/home/alice"
chmod 666 "$L/var/cron/tabs/alice"
printf '0 * * * * /bin/true\n' > "$L/var/cron/tabs/ghost"; chmod 600 "$L/var/cron/tabs/ghost"
printf '5 4 * * * root newsyslog\n' >> "$L/etc/crontab"
sed -i 's/:umask=022:/:umask=020:/; s/^default:/standard|default:/' "$L/etc/login.conf"
chmod 644 "$L/etc/master.passwd"; chmod 666 "$L/etc/rc.conf"

#
# check_passwd
#
run check_passwd "$C"
noerr && [ "`count .`" = 0 ] && ok "check_passwd, clean master.passwd: runs, silent" || { bad "passwd clean"; cat "$W/raw"; }
run check_passwd "$L"
noerr && has '[pass017w] Login ID toor has uid == 0.' && has '[pass014w] Login (bob) is disabled, but has a valid shell.' &&
  has '[pass013w] Username `eve'"'"' is not using an acceptable password hash (bsdicrypt).' && has '[pass015w] Login ID toor has an empty shell.' &&
  [ "`count pass007w`" = 0 ] &&
  ok "check_passwd: toor, pw lock's *LOCKED*, extended DES; master.passwd is the shadow file" || { bad "passwd loose"; cat "$W/raw"; }

#
# check_passwdformat (run with check_passwd on an offline root): the
# installed files' comment lines are FreeBSD's to have
#
run check_passwdformat "$C"
noerr && grep -q '^# \$FreeBSD\$' "$C/etc/passwd" && grep -q '^#' "$C/etc/group" && [ "`count .`" = 0 ] &&
  ok "check_passwdformat, clean: comment lines in passwd and group are no malformed entries" || { bad "passwdformat clean"; cat "$W/raw"; }
run check_passwdformat "$L"
noerr && has '[pass009f] Login toor has a user id of 0 which should be reserved for root' &&
  ok "check_passwdformat: toor's uid 0: pass009f" || { bad "passwdformat loose"; cat "$W/raw"; }

#
# check_group
#
run check_group "$C"
noerr && [ "`count .`" = 0 ] && ok "check_group, clean: runs, silent" || { bad "group clean"; cat "$W/raw"; }
run check_group "$L"
noerr && has "[grp001w] Groupname \`wheel' exists multiple times in /etc/group." &&
  ok "check_group: a group twice: grp001w" || { bad "group loose"; cat "$W/raw"; }

#
# check_accounts
#
run check_accounts "$C"
noerr && [ "`count .`" = 0 ] && ok "check_accounts, clean: runs, silent" || { bad "accounts clean"; cat "$W/raw"; }
run check_accounts "$L"
noerr && has "[acc006w] Login ID alice's home directory (/home/alice) has" && has "world write access." && [ "`count .`" = 1 ] &&
  ok "check_accounts: a world-writable home: acc006w, and only that" || { bad "accounts loose"; cat "$W/raw"; }
cp "$L/var/cron/tabs/alice" "$L/var/cron/tabs/bob"
run check_accounts "$L"
has "[acc005w] Login ID bob is disabled, but has a 'cron' file or cron entries." &&
  ok "check_accounts: a locked account's crontab in /var/cron/tabs: acc005w" || { bad "accounts cron"; cat "$W/raw"; }
rm -f "$L/var/cron/tabs/bob"

#
# check_crontabs
#
run check_crontabs "$C"
noerr && [ "`count .`" = 0 ] && ok "check_crontabs, clean: runs, silent (root's crontab is /etc/crontab's)" || { bad "crontabs clean"; cat "$W/raw"; }
run check_crontabs "$L"
noerr && has "[cron008f] \`/var/cron/tabs/alice' is writable by everyone: anyone can have cron run commands as alice." &&
  has "[cron010w] \`/var/cron/tabs/ghost' is a crontab for ghost" &&
  has '[cron001w] cron entry for root does not use full pathname (newsyslog):' &&
  ok "check_crontabs: /var/cron/tabs read, an orphan tab, a relative command" || { bad "crontabs loose"; cat "$W/raw"; }
chmod 666 "$L/usr/local/etc/cron.d/backup"; chmod 777 "$L/etc/periodic/daily/100.clean-disks"
run check_crontabs "$L"
has "[cron008f] \`/usr/local/etc/cron.d/backup' is writable by everyone" &&
  has "[cron008f] \`/etc/periodic/daily/100.clean-disks' is writable by everyone" &&
  ok "check_crontabs: /usr/local/etc/cron.d and the periodic scripts are cron's files" || { bad "crontabs dirs"; cat "$W/raw"; }
chmod 644 "$L/usr/local/etc/cron.d/backup"; chmod 555 "$L/etc/periodic/daily/100.clean-disks"
rm -f "$L/var/cron/deny"
run check_crontabs "$L"
has '[cron005w] Use of cron is not restricted' &&
  ok "check_crontabs: neither /var/cron/allow nor /var/cron/deny: cron005w" || { bad "crontabs allow"; cat "$W/raw"; }
printf 'alice\n' > "$L/var/cron/allow"
run check_crontabs "$L"
has '[cron006w] User alice is allowed cron usage.' && [ "`count cron005w`" = 0 ] &&
  ok "check_crontabs: /var/cron/allow is FreeBSD's cron.allow" || { bad "crontabs allow file"; cat "$W/raw"; }

#
# check_umask
#
run check_umask "$C"
noerr && [ "`count .`" = 0 ] && ok "check_umask, clean: profile without umask is no finding on FreeBSD, login.conf's 022 is fine" || { bad "umask clean"; cat "$W/raw"; }
run check_umask "$L"
noerr && has '[misc022f] The umask setting in /etc/login.conf is insecure (020 lets others write)' && [ "`count misc021w`" = 0 ] &&
  ok "check_umask: login.conf's default class lets others write: misc022f" || { bad "umask loose"; cat "$W/raw"; }

#
# check_issue
#
run check_issue "$C"
noerr && grep -q '/etc/issue is not shown at login on FreeBSD: not checked.' "$W/raw" && [ "`count .`" = 0 ] &&
  ok "check_issue: does not apply, says so, no init001e" || { bad "issue"; cat "$W/raw"; }

#
# check_perms
#
run check_perms "$C"
noerr && [ "`count .`" = 0 ] && ok "check_perms, clean: FreeBSD's database read, silent" || { bad "perms clean"; cat "$W/raw"; }
run check_perms "$L"
noerr && has '[perm001w] /etc/master.passwd should not have world read.' &&
  has '[perm001w] /etc/rc.conf should not have world write.' &&
  ok "check_perms: master.passwd readable, rc.conf writable" || { bad "perms loose"; cat "$W/raw"; }

#
# check_path, which runs now too: the initial PATH is login.conf's
#
run check_path "$C"
noerr && [ "`count .`" = 0 ] && ok "check_path, clean: login.conf's path capability sets PATH, no start-up file need" || { bad "path clean"; cat "$W/raw"; }
sed -i '/:path=/d' "$L/etc/login.conf"
run check_path "$L"
noerr && has '[path009w] /etc/profile does not export an initial setting for PATH.' && has '[path009w] /etc/csh.login does not setenv' &&
  ok "check_path: no path capability, none in the start-up files: path009w" || { bad "path loose"; cat "$W/raw"; }

#
# gen_mounts: mount's lines, FreeBSD's and macOS's, for check_perms'
# disk devices (a live leg, so read here from a stand-in mount)
#
cat > "$W/mount-stub" <<'EOF'
#!/bin/sh
cat <<'EOT'
/dev/ada0p2 on / (ufs, local, soft-updates)
zroot/ROOT/default on /zroot (zfs, local, noatime, nfsv4acls)
devfs on /dev (devfs)
procfs on /proc (procfs, local)
fdescfs on /dev/fd (fdescfs)
tmpfs on /tmp (tmpfs, local)
/usr/home on /jail/home (nullfs, local)
nas:/export on /mnt/nas (nfs)
/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
/dev/disk5s1 on /Volumes/Back Up (hfs, local, nodev, nosuid, journaled)
map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)
EOT
EOF
chmod 755 "$W/mount-stub"
( cd "$W" && OS=FreeBSD TIGERHOMEDIR=$W Tigris_Mounts_Cmd="$W/mount-stub" sh -c '. ./config >/dev/null 2>&1; $GET_MOUNTS local all; echo ==; $GET_MOUNTS local rw' ) > "$W/mounts" 2>&1
printf '%s\n' '/ ufs /dev/ada0p2' '/zroot zfs zroot/ROOT/default' '/tmp tmpfs tmpfs' '/ apfs /dev/disk3s1s1' '/Volumes/Back\ Up hfs /dev/disk5s1' \
  '==' '/ ufs /dev/ada0p2' '/zroot zfs zroot/ROOT/default' '/tmp tmpfs tmpfs' '/Volumes/Back\ Up hfs /dev/disk5s1' > "$W/mounts.want"
cmp -s "$W/mounts" "$W/mounts.want" &&
  ok "gen_mounts: local file systems from mount's lines, not devfs, procfs, nullfs, NFS or autofs; read-only ones left out with rw" ||
  { bad "gen_mounts"; diff "$W/mounts.want" "$W/mounts"; }

#
# tigris itself, on the clean root, with these checks
#
{
  sed -n 's/^\(Tigris_Check_[A-Z_]*\)=.*/\1=N/p' "$W/tigris.conf"
  for c in PASSWD GROUP ACCOUNTS CRON USERUMASK PERMS; do echo "Tigris_Check_$c=Y"; done
} > "$W/profiles/bsd"
chmod 644 "$W/profiles/bsd"
( cd "$W" && OS=FreeBSD REV=14.1-RELEASE ARCH=amd64 sh ./tigris -q --profile bsd --root "$C" ) > "$W/raw" 2>&1
report=`ls "$W"/log/security.report.* 2>/dev/null | grep -v '\.jsonl$' | head -1`
# (as a user, the two checks that need root say they were skipped)
if [ "$uid" = 0 ]; then passwd='Performing check of passwd files'; else passwd='Skipped check_passwd: it needs root'; fi
[ -n "$report" ] && ! grep -q 'init00\|--ERROR--\|not found' "$W/raw" "$report" &&
  grep -q 'Beginning security report for .* FreeBSD 14.1-RELEASE' "$report" && grep -q "$passwd" "$report" &&
  grep -q 'Checking the format of passwd and group files' "$report" && grep -q 'Performing check of user accounts' "$report" &&
  grep -q "Performing check of \`cron' entries" "$report" && grep -q 'Performing check of system file permissions' "$report" &&
  grep -q 'Checking for correct umask settings' "$report" && grep -q '# Summary: 0 ALERT, 0 FAIL, 0 WARN' "$report" &&
  ok "tigris --root with the FreeBSD config: runs its checks, nothing to report, no init001e" || { bad "tigris"; cat "$W/raw" $report; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
