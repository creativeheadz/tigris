#!/bin/sh
#
# tests/logfiles_check.sh - Linux check_logfiles: log rotation, and the
# configured syslog daemon running
#
# Offline roots (TIGRIS_ROOT): rsyslog writing five files with Debian's
# logrotate entry and logrotate.timer enabled (silent); the same without
# a logrotate program (logf011w: not installed); logrotate without
# /etc/logrotate.conf (logf011w: no configuration); an entry covering
# /var/log/syslog alone (logf011w naming the other files, not syslog);
# everything covered by /var/log/*.log with no timer or cron job
# (logf011w: nothing runs it); a journal-only root (silent); syslog-ng
# with file() destinations and a dynamic $YEAR name (left out), rotated
# through an include directory of its own; the classic syslog.conf with
# a syslogd, rotated from cron.d. Live (Tigris_Sysctl_Root): rsyslog
# configured, no rsyslogd running, no persistent journal (logf012w);
# rsyslogd running (silent); the journal on disk (silent). The portable
# legs (wtmp, btmp, lastlog) fail on these roots as they should, and
# are not looked at here. Runs as a user and as root.
#
TIGER=${TIGER:-`cd "\`dirname \"$0\"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
join() {
  awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' | grep 'logf011w\|logf012w'
}
run() {  # run ROOT: check_logfiles with ROOT as the audited (offline) system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./scripts/check_logfiles ) 2>&1 | join > "$W/out" || true
}
live() {  # live ROOT: the same, live, with /proc and the files under ROOT
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  echo "Tigris_Sysctl_Root='$1'" >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./scripts/check_logfiles ) 2>&1 | join > "$W/out" || true
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }
prog() { mkdir -p "${1%/*}"; printf '\177ELF\n' > "$1"; chmod 755 "$1"; }   # prog PATH

# rsyslog ROOT: Debian's rsyslog.conf and 50-default.conf, five files
# written (and mail.err, as the stock rules name it, not yet created)
rsyslog() {
  mkdir -p "$1/etc/rsyslog.d" "$1/var/log"
  for f in auth.log syslog kern.log mail.log app.log; do echo log > "$1/var/log/$f"; done
  cat > "$1/etc/rsyslog.conf" <<'EOF'
module(load="imuxsock")
module(load="imklog")
$WorkDirectory /var/spool/rsyslog
$IncludeConfig /etc/rsyslog.d/*.conf
EOF
  cat > "$1/etc/rsyslog.d/50-default.conf" <<'EOF'
auth,authpriv.*			/var/log/auth.log
*.*;auth,authpriv.none		-/var/log/syslog
kern.*				-/var/log/kern.log
mail.*				-/var/log/mail.log
mail.err			/var/log/mail.err
*.emerg				:omusrmsg:*
if $programname == 'app' then /var/log/app.log
action(type="omfwd" target="loghost.example" port="514")
EOF
}
# logrotate ROOT: the program, logrotate.conf including logrotate.d
logrotate() {
  prog "$1/usr/sbin/logrotate"
  mkdir -p "$1/etc/logrotate.d"
  printf 'weekly\nrotate 4\ncreate\ninclude /etc/logrotate.d\n/var/log/wtmp {\n\tmonthly\n\tcreate 0664 root utmp\n\trotate 1\n}\n' > "$1/etc/logrotate.conf"
}
timer() { mkdir -p "$1/etc/systemd/system/timers.target.wants"; ln -s /usr/lib/systemd/system/logrotate.timer "$1/etc/systemd/system/timers.target.wants/logrotate.timer"; }

G=$W/good; rsyslog "$G"; logrotate "$G"; timer "$G"
printf '/var/log/syslog\n/var/log/mail.log\n/var/log/kern.log\n/var/log/auth.log\n/var/log/user.log\n/var/log/*.log\n{\n\trotate 4\n\tweekly\n\tmissingok\n\tpostrotate\n\t\t/usr/lib/rsyslog/rsyslog-rotate\n\tendscript\n}\n' > "$G/etc/logrotate.d/rsyslog"
run "$G"
[ -s "$W/out" ] && { bad "good"; cat "$W/out"; } || ok "rsyslog's files all in logrotate.d, logrotate.timer enabled: nothing said (mail.err, not yet created, is not judged)"
echo err > "$G/var/log/mail.err"
run "$G"
has '[logf011w] rsyslog writes log files that no logrotate entry rotates' && has 'Rotated by nothing: /var/log/mail.err.' &&
  ok "the stock mail.err, once it exists: logf011w names it" || { bad "mail.err"; cat "$W/out"; }
rm "$G/var/log/mail.err"

N=$W/nolr; rsyslog "$N"
run "$N"
has '--WARN-- [logf011w] rsyslog writes 5 log files and logrotate is not installed' && has '/var/log/app.log, /var/log/auth.log, /var/log/kern.log, /var/log/mail.log, /var/log/syslog.' &&
  ok "no logrotate: logf011w, naming the five files (a forwarding action and :omusrmsg: are not files)" || { bad "nolr"; cat "$W/out"; }

C=$W/noconf; rsyslog "$C"; prog "$C/usr/sbin/logrotate"; timer "$C"
run "$C"
has '--WARN-- [logf011w] rsyslog writes 5 log files and logrotate has no /etc/logrotate.conf' &&
  ok "logrotate without logrotate.conf: logf011w" || { bad "noconf"; cat "$W/out"; }

P=$W/partial; rsyslog "$P"; logrotate "$P"; timer "$P"
printf '/var/log/syslog\n{\n\trotate 7\n\tdaily\n}\n' > "$P/etc/logrotate.d/rsyslog"
run "$P"
has '--WARN-- [logf011w] rsyslog writes log files that no logrotate entry rotates' && has 'Rotated by nothing: /var/log/app.log, /var/log/auth.log, /var/log/kern.log, /var/log/mail.log.' &&
[ "`count '/var/log/syslog'`" = 0 ] &&
  ok "an entry for syslog alone: logf011w names the other four, not syslog" || { bad "partial"; cat "$W/out"; }

R=$W/norun; rsyslog "$R"; logrotate "$R"
printf '"/var/log/syslog" /var/log/*.log {\n\trotate 7\n\tdaily\n}\n' > "$R/etc/logrotate.d/rsyslog"
run "$R"
has '--WARN-- [logf011w] logrotate is installed and configured for the 5 log files rsyslog writes, but no timer or cron job runs it' &&
  ok "everything matched by a quoted name and a glob, nothing running logrotate: logf011w" || { bad "norun"; cat "$W/out"; }
mkdir -p "$R/etc/cron.daily"; printf '#!/bin/sh\n/usr/sbin/logrotate /etc/logrotate.conf\n' > "$R/etc/cron.daily/logrotate"
run "$R"
[ -s "$W/out" ] && { bad "cron.daily"; cat "$W/out"; } || ok "the same with /etc/cron.daily/logrotate: nothing said"

J=$W/journal; mkdir -p "$J/etc/systemd" "$J/var/log/journal/abc"
printf '[Journal]\nStorage=persistent\n' > "$J/etc/systemd/journald.conf"
run "$J"
[ -s "$W/out" ] && { bad "journal"; cat "$W/out"; } || ok "journal only, no syslog daemon configured: nothing to rotate, nothing said"

S=$W/ng; mkdir -p "$S/etc/syslog-ng/conf.d" "$S/etc/logrotate.d" "$S/etc/logrotate.site" "$S/var/log"
for f in messages auth.log mail.log; do echo log > "$S/var/log/$f"; done
cat > "$S/etc/syslog-ng/syslog-ng.conf" <<'EOF'
@version: 4.3
source s_src { system(); internal(); file("/proc/kmsg" program_override("kernel")); };
destination d_messages { file("/var/log/messages"); };
destination d_auth { file("/var/log/auth.log"); };
destination d_console { file("/dev/tty10"); };
destination d_daily { file("/var/log/daily/$YEAR.$MONTH.$DAY/messages"); };
@include "conf.d/*.conf"
EOF
printf 'destination d_mail { file("/var/log/mail.log"); };\n' > "$S/etc/syslog-ng/conf.d/mail.conf"
prog "$S/usr/sbin/logrotate"
printf 'include /etc/logrotate.d\ninclude /etc/logrotate.site\n' > "$S/etc/logrotate.conf"
printf '/var/log/messages /var/log/auth.log {\n\trotate 4\n}\n' > "$S/etc/logrotate.d/syslog-ng"
printf '/var/log/mail.log {\n\trotate 4\n}\n' > "$S/etc/logrotate.site/mail"
timer "$S"
run "$S"
[ -s "$W/out" ] && { bad "syslog-ng"; cat "$W/out"; } || ok "syslog-ng: file() destinations rotated through two include directories; /proc, /dev and a \$YEAR name left out"
rm "$S/etc/logrotate.site/mail"
run "$S"
has '[logf011w] syslog-ng writes log files that no logrotate entry rotates' && has 'Rotated by nothing: /var/log/mail.log.' &&
  ok "syslog-ng: the entry gone, logf011w names mail.log alone" || { bad "syslog-ng gone"; cat "$W/out"; }

K=$W/classic; mkdir -p "$K/etc/cron.d" "$K/etc/logrotate.d" "$K/var/log"
for f in messages maillog; do echo log > "$K/var/log/$f"; done
prog "$K/usr/sbin/syslogd"; prog "$K/usr/sbin/logrotate"
printf '*.info;mail.none\t\t-/var/log/messages\nmail.*\t\t\t/var/log/maillog\n*.emerg\t\t\t*\n' > "$K/etc/syslog.conf"
printf 'include /etc/logrotate.d\n' > "$K/etc/logrotate.conf"
printf '/var/log/messages /var/log/maillog {\n\trotate 4\n}\n' > "$K/etc/logrotate.d/syslog"
printf '# rotate the logs\n30 3 * * * root /usr/sbin/logrotate /etc/logrotate.conf\n' > "$K/etc/cron.d/logrotate"
run "$K"
[ -s "$W/out" ] && { bad "classic"; cat "$W/out"; } || ok "the classic syslog.conf with a syslogd, rotated from cron.d: nothing said"
printf '# 30 3 * * * root /usr/sbin/logrotate /etc/logrotate.conf\n' > "$K/etc/cron.d/logrotate"
run "$K"
has '[logf011w] logrotate is installed and configured for the 2 log files syslogd writes, but no timer or cron job runs it' &&
  ok "the cron.d line commented out: logf011w" || { bad "classic commented"; cat "$W/out"; }

# live: the configured daemon not running
L=$W/live; rsyslog "$L"; logrotate "$L"; timer "$L"
printf '/var/log/*.log /var/log/syslog {\n\trotate 4\n}\n' > "$L/etc/logrotate.d/rsyslog"
mkdir -p "$L/proc/1" "$L/proc/2" "$L/var/log"
echo systemd > "$L/proc/1/comm"; echo systemd-journal > "$L/proc/2/comm"
live "$L"
has '--WARN-- [logf012w] rsyslog is configured but no syslog daemon is running, and the journal is not kept on disk' && [ "`count logf011w`" = 0 ] &&
  ok "live: rsyslog configured, not running, no persistent journal: logf012w" || { bad "live dead"; cat "$W/out"; }
mkdir -p "$L/proc/3"; echo rsyslogd > "$L/proc/3/comm"
live "$L"
[ -s "$W/out" ] && { bad "live running"; cat "$W/out"; } || ok "live: rsyslogd running: nothing said"
rm -rf "$L/proc/3"; mkdir -p "$L/var/log/journal/0123"; : > "$L/var/log/journal/0123/system.journal"
live "$L"
[ -s "$W/out" ] && { bad "live journal"; cat "$W/out"; } || ok "live: rsyslogd stopped but the journal on disk: nothing said"
rm -rf "$L/var/log/journal"
run "$L"
[ "`count logf012w`" = 0 ] && ok "offline: the running daemon is not judged" || { bad "offline dead"; cat "$W/out"; }
grep -q "$W" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
