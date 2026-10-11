#!/bin/sh
#
# tests/audit_check.sh - check_audit against trees and an auditctl of its own
#
# The running processes are /proc/PID/comm files under Tiger_Sysctl_Root,
# auditctl -l is a script through Tiger_Auditctl_Cmd, and journald's
# configuration is journald.conf and drop-ins under the same root, to
# show that the last Storage= in systemd's order wins: drop-ins by file
# name, one in /etc hiding the same name in /usr/lib.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigerrc" "$W/tigerrc.base"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# root NAME PROCESS...: a tree with these processes running and journald up
root() {
  r="$W/$1"; shift; mkdir -p "$r/proc" "$r/run/systemd/journal" "$r/etc/systemd"
  n=1
  for p in systemd systemd-journal "$@"; do mkdir -p "$r/proc/$n"; echo "$p" > "$r/proc/$n/comm"; n=$((n + 1)); done
}
printf '#!/bin/sh\nprintf "%%s\\n" "-w /etc/passwd -p wa -k identity" "-a always,exit -F arch=b64 -S execve -F euid=0 -k rootcmd"\n' > "$W/ac-rules"
printf '#!/bin/sh\necho "No rules"\n' > "$W/ac-none"
printf '#!/bin/sh\necho "You must be root to run this program." >&2\nexit 4\n' > "$W/ac-denied"
go() {  # go NAME AUDITCTL-SCRIPT
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$W/$1'"; echo "Tiger_Auditctl_Cmd='sh $W/$2'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_audit ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

root ok auditd; mkdir -p "$W/ok/var/log/journal"
go ok ac-rules
has '--INFO-- [aud003i] auditd is running with 2 rules loaded.' && [ "`count .`" = 1 ] &&
  ok "auditd with rules, journal on disk: one INFO" || { bad "rules"; cat "$W/out"; }
go ok ac-none
has '--WARN-- [aud002w] auditd is running with no rules loaded' && ok "auditd without rules: aud002w" || { bad "no rules"; cat "$W/out"; }
go ok ac-denied
has '--ERROR-- [aud004e] auditd is running, but its rules cannot be listed' && has 'You must be root' &&
  ok "auditctl refused: aud004e with its error" || { bad "denied"; cat "$W/out"; }
root noaudit; mkdir -p "$W/noaudit/var/log/journal"
go noaudit ac-rules
has '--WARN-- [aud001w] auditd is not running' && [ "`count .`" = 1 ] && ok "no auditd: aud001w" || { bad "no auditd"; cat "$W/out"; }

# journald
root volatile auditd; printf '[Journal]\nStorage=volatile\n' > "$W/volatile/etc/systemd/journald.conf"
go volatile ac-rules
has '--WARN-- [logf008w] Logs are not kept across reboots' && has 'journald: Storage=volatile, and no syslog daemon is running.' &&
  ok "Storage=volatile, no syslog: logf008w" || { bad "volatile"; cat "$W/out"; }
root volsyslog auditd rsyslogd; printf '[Journal]\nStorage=volatile\n' > "$W/volsyslog/etc/systemd/journald.conf"
go volsyslog ac-rules
[ "`count logf008w`" = 0 ] && ok "Storage=volatile with rsyslogd running: logs are kept" || { bad "rsyslog"; cat "$W/out"; }
root auto auditd
go auto ac-rules
has 'journald: Storage=auto, and /var/log/journal does not exist' && ok "Storage=auto without /var/log/journal: logf008w" || { bad "auto"; cat "$W/out"; }
root drop auditd
printf '[Journal]\nStorage=persistent\n' > "$W/drop/etc/systemd/journald.conf"
mkdir -p "$W/drop/usr/lib/systemd/journald.conf.d" "$W/drop/etc/systemd/journald.conf.d"
printf '[Journal]\nStorage=volatile\n' > "$W/drop/usr/lib/systemd/journald.conf.d/10-vendor.conf"
printf '[Journal]\nSystemMaxUse=1G\n' > "$W/drop/etc/systemd/journald.conf.d/10-vendor.conf"
go drop ac-rules
[ "`count logf008w`" = 0 ] && ok "a drop-in in /etc hides the one of the same name in /usr/lib, Storage= and all" || { bad "drop-in hiding"; cat "$W/out"; }
printf '[Journal]\nStorage=volatile\n' > "$W/drop/usr/lib/systemd/journald.conf.d/20-later.conf"
go drop ac-rules
has 'journald: Storage=volatile' && ok "a later drop-in, by name, wins over /etc's" || { bad "drop-in order"; cat "$W/out"; }
mkdir -p "$W/nojournald/proc/1"; echo auditd > "$W/nojournald/proc/1/comm"
go nojournald ac-rules
[ "`count logf008w`" = 0 ] && ok "no journald: nothing said about it" || { bad "no journald"; cat "$W/out"; }
# journald found by its process alone, as /proc shows it (15 characters)
mkdir -p "$W/byproc/proc/1" "$W/byproc/proc/2" "$W/byproc/etc/systemd"
echo auditd > "$W/byproc/proc/1/comm"; echo systemd-journal > "$W/byproc/proc/2/comm"
printf '[Journal]\nStorage=volatile\n' > "$W/byproc/etc/systemd/journald.conf"
go byproc ac-rules
has '[logf008w]' && ok "journald found by its 15-character process name" || { bad "journald by process"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
