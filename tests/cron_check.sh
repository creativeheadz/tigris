#!/bin/sh
#
# tests/cron_check.sh - check_crontabs and gen_cron on a root of their own
#
# Builds a root (TIGRIS_ROOT, as tigris --root sets it) with cron jobs in
# every place cron reads them, and problems planted: a cron.d file anyone
# can write (cron008f), a cron.daily script its group can write (cron008w),
# a cron.d file that is not root's (cron009w), a job that runs a script
# anyone can write, with "--" among its arguments (which used to drop the
# job), a job by a relative path in a user's crontab (cron001w), a spool
# crontab for no account (cron010w), and one whose name is a command: it
# must not be run. An at.allow naming a user (cron011w) and an at.deny
# naming one (cron012i) must both be reported. A cron.d file whose name cron ignores (it has a dot)
# must be ignored, and /etc/crontab's "test -x ... ||" must not count as a
# relative path. Runs as a user and as root (then the system's files are
# given to root and the rest to an ordinary uid).
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
# INFO findings (at.deny among them) are silent by default
echo "Tiger_Show_INFO_Msgs=Y" >> "$W/tigerrc"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
uid=`id -u`
[ "$uid" = 0 ] && chown -R 0:0 "$W"
U=$uid; G=`id -g`
[ "$uid" = 0 ] && { U=4242; G=4242; }

R=$W/img
mkdir -p "$R/etc/cron.d" "$R/etc/cron.daily" "$R/var/spool/cron/crontabs" "$R/opt/backup" "$R/home/milo"
printf 'root:x:0:0:root:/root:/bin/sh\nmilo:x:%s:%s:Milo:/home/milo:/bin/sh\n' "$U" "$G" > "$R/etc/passwd"
cat > "$R/etc/crontab" <<'EOF'
SHELL=/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
17 *	* * *	root	cd / && run-parts --report /etc/cron.hourly
25 6	* * *	root	test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.daily; }
EOF
echo '0 2 * * * root /opt/backup/run.sh --full --quiet' > "$R/etc/cron.d/backup"
echo '0 3 * * * root /usr/bin/true' > "$R/etc/cron.d/world"
echo '0 4 * * * root /usr/bin/true' > "$R/etc/cron.d/owned"
echo '0 5 * * * root relative-and-ignored' > "$R/etc/cron.d/old.dpkg-old"
# as sysstat, e2fsprogs and Pi-hole ship them on Debian and Ubuntu: a
# builtin first, VAR=value before the command
cat > "$R/etc/cron.d/stock" <<'EOF'
PATH=/usr/lib/sysstat:/usr/sbin:/usr/bin:/sbin:/bin
5-55/10 * * * * root command -v debian-sa1 > /dev/null && debian-sa1 1 1
30 3 * * 0 root test -e /run/systemd/system || SERVICE_MODE=1 /usr/lib/x86_64-linux-gnu/e2fsprogs/e2scrub_all_cron
10 3 * * * root SERVICE_MODE=1 /sbin/e2scrub_all -A -r
49 4 * * 7 root PATH="$PATH:/usr/sbin:/usr/local/bin/" pihole updateGravity >/var/log/pihole_updateGravity.log || cat /var/log/pihole_updateGravity.log
EOF
printf '#!/bin/sh\n' > "$R/opt/backup/run.sh"
printf '#!/bin/sh\n' > "$R/etc/cron.daily/logrotate"
printf 'milo\n' > "$R/etc/at.allow"
printf 'ghost\n' > "$R/etc/at.deny"
echo '@daily backup.sh' > "$R/var/spool/cron/crontabs/milo"
echo '@daily /usr/bin/true' > "$R/var/spool/cron/crontabs/ghost"
# (the check runs in $W, so a name that is run leaves $W/ran)
echo '@daily /usr/bin/true' > "$R/var/spool/cron/crontabs/\$(touch ran)"
chmod 644 "$R/etc/crontab" "$R/etc/cron.d/"*
chmod 777 "$R/opt/backup/run.sh"
chmod 666 "$R/etc/cron.d/world"
chmod 775 "$R/etc/cron.daily/logrotate"
chmod 600 "$R/var/spool/cron/crontabs/"*
if [ "$uid" = 0 ]; then
  chown -R 0:0 "$R"
  chown "$U:$G" "$R/etc/cron.d/owned" "$R/var/spool/cron/crontabs/milo" "$R/home/milo"
fi

( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh scripts/check_crontabs 2>&1 ) |
  awk '/^--/ { if (l != "") print l; l = $0; next } /^[ \t]/ { sub(/^[ \t]+/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' > "$W/out"
has() { grep -F -q -- "$1" "$W/out"; }

has "[cron008f] \`/etc/cron.d/world' is writable by everyone: anyone can have cron run commands as root." &&
  ok "a cron.d file anyone can write: cron008f" || bad "cron008f"
has "[cron008w] \`/etc/cron.daily/logrotate' is writable by group" && ok "a cron.daily script its group can write: cron008w" || bad "cron008w"
has "[cron009w] \`/etc/cron.d/owned' is owned by milo, not root" &&
  ok "a cron.d file that is not root's, named by the root's passwd: cron009w" || bad "cron009w"
has "[cron003f] cron entry for root uses \`/opt/backup/run.sh' which is" && has '/opt/backup/run.sh --full --quiet' &&
  ok "a job running a script anyone can write, '--' in its arguments and all: cron003f" || bad "cron003f"
has "[cron001w] cron entry for milo does not use full pathname (backup.sh)" && ok "a relative path in a user's crontab: cron001w" || bad "cron001w"
has "[cron010w] \`/var/spool/cron/crontabs/ghost' is a crontab for ghost, which is no account here" &&
  ok "a spool crontab for no account: cron010w" || bad "cron010w"
[ -e "$W/ran" ] && bad "a crontab's file name was run" || ok "a crontab named \$(touch ...) is reported, not run"
has 'relative-and-ignored' && bad "a cron.d file cron ignores (a dot in its name) was read" || ok "a cron.d file whose name cron ignores is left out"
has '(test)' && bad "a shell builtin counted as a relative path" || ok "/etc/crontab's 'test -x ... ||' is not a relative path"
has '(command)' && bad "the builtin command counted as a relative path" || ok "sysstat's 'command -v debian-sa1 && ...' is not a relative path"
has 'pathname (SERVICE_MODE=1)' || has 'pathname (PATH=' && bad "VAR=value before a command was taken for the command" ||
  ok "VAR=value before a command is not the command"
has "[cron001w] cron entry for root does not use full pathname (pihole)" &&
  ok "the command after VAR=value is: Pi-hole's relative pihole is cron001w" || bad "pihole after PATH=..."
has "[cron009w] \`/var/spool/cron/crontabs/milo'" && bad "milo's own crontab reported as not his" || ok "a user's crontab may be the user's"
has "[cron011w] User milo is allowed at usage." && ok "at.allow names a user: cron011w" || bad "cron011w"
has "[cron012i] User ghost is denied at usage." && ok "at.deny names a user: cron012i" || bad "cron012i"
grep -q "$R" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/out"; }
exit $fail
