#!/bin/sh
#
# tests/timesync_check.sh - check_timesync against process trees of its own
#
# The running processes are /proc/PID/comm files under Tiger_Sysctl_Root,
# with the names /proc really shows (systemd-timesyn, 15 characters);
# timedatectl show and chronyc -n tracking are scripts printing what the
# real ones print, through Tiger_Timedatectl_Cmd and Tiger_Chronyc_Cmd.
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

procs() {  # procs NAME COMM...
  r="$W/$1"; shift; n=1
  for p in systemd "$@"; do mkdir -p "$r/proc/$n"; echo "$p" > "$r/proc/$n/comm"; n=$((n + 1)); done
}
printf '#!/bin/sh\nprintf "%%s\\n" Timezone=Europe/London NTP=yes NTPSynchronized=%s\n' yes > "$W/tdc-yes"
printf '#!/bin/sh\nprintf "%%s\\n" Timezone=Europe/London NTP=yes NTPSynchronized=%s\n' no > "$W/tdc-no"
cat > "$W/chrony-ok" <<'EOF'
#!/bin/sh
cat <<EOT
Reference ID    : C0A80101 (ntp.example.org)
Stratum         : 3
Ref time (UTC)  : Wed Oct 07 13:02:11 2026
System time     : 0.000012 seconds fast of NTP time
Leap status     : Normal
EOT
EOF
cat > "$W/chrony-unsync" <<'EOF'
#!/bin/sh
cat <<EOT
Reference ID    : 00000000 ()
Stratum         : 0
Leap status     : Not synchronised
EOT
EOF
go() {  # go NAME TIMEDATECTL CHRONYC
  cp "$W/tigerrc.base" "$W/tigerrc"
  { echo "Tiger_Sysctl_Root='$W/$1'"; echo "Tiger_Timedatectl_Cmd='sh $W/$2'"; echo "Tiger_Chronyc_Cmd='sh $W/$3'"; echo "Tiger_Show_INFO_Msgs=Y"; } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_timesync ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

procs tsd systemd-timesyn
go tsd tdc-yes chrony-ok
has '--INFO-- [time003i] The clock is synchronised by systemd-timesyncd.' && [ "`count .`" = 1 ] &&
  ok "systemd-timesyncd (as /proc names it), synchronised: time003i" || { bad "timesyncd"; cat "$W/out"; }
go tsd tdc-no chrony-ok
has '--WARN-- [time002w] systemd-timesyncd is running, but the clock is not synchronised.' && ok "timesyncd not synchronised: time002w" || { bad "timesyncd unsync"; cat "$W/out"; }
procs chr chronyd
go chr tdc-no chrony-ok
has 'The clock is synchronised by chronyd (from ntp.example.org).' && [ "`count time002w`" = 0 ] &&
  ok "chronyd: chronyc decides, not timedatectl (which says no without rtcsync)" || { bad "chrony"; cat "$W/out"; }
go chr tdc-yes chrony-unsync
has '--WARN-- [time002w] chronyd is running, but the clock is not synchronised.' && ok "chronyd not synchronised: time002w" || { bad "chrony unsync"; cat "$W/out"; }
procs none sshd cron
go none tdc-yes chrony-ok
has '--WARN-- [time001w] No time synchronisation daemon is running' && [ "`count .`" = 1 ] && ok "no daemon: time001w" || { bad "none"; cat "$W/out"; }
procs two chronyd systemd-timesyn
go two tdc-yes chrony-ok
has '--WARN-- [time004w] More than one time synchronisation daemon is running' && has 'Running: chronyd systemd-timesyncd.' &&
  ok "two daemons: time004w, naming both" || { bad "two"; cat "$W/out"; }
procs ctr; : > "$W/ctr/.dockerenv"
go ctr tdc-yes chrony-ok
[ "`count .`" = 0 ] && ok "a container: nothing said" || { bad "container"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
