#!/bin/sh
#
# tests/timesync_check.sh - check_timesync against process trees of its own
#
# The running processes are /proc/PID/comm files under Tigris_Sysctl_Root,
# with the names /proc really shows (systemd-timesyn, 15 characters);
# timedatectl show, chronyc -n tracking, chronyc -n sources and ntpq -pn
# are scripts printing what the real ones print, through
# Tigris_Timedatectl_Cmd, Tigris_Chronyc_Cmd, Tigris_Chronyc_Sources_Cmd
# and Tigris_Ntpq_Cmd. The ntpq with pools prints what ntpsec 1.2.3 on
# Debian stable prints; the hung one never answers, and the check must
# give up on it (when this system has a timeout command).
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
cp "$W/tigris.conf" "$W/tigris.conf.base"
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
cat > "$W/sources-ok" <<'EOF'
#!/bin/sh
cat <<EOT
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^- 192.0.2.10                    2   6   377    21    +15us[ +30us] +/-  123us
^* 192.0.2.11                    2   6   377    20    -10us[ -25us] +/-  110us
^+ 192.0.2.12                    3   6   377    19    +40us[ +55us] +/-  200us
^+ 192.0.2.13                    2   6   377    18     +5us[ +12us] +/-   95us
EOT
EOF
cat > "$W/sources-false" <<'EOF'
#!/bin/sh
cat <<EOT
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^- 192.0.2.10                    2   6   377    21    +15us[ +30us] +/-  123us
^* 192.0.2.11                    2   6   377    20    -10us[ -25us] +/-  110us
^+ 192.0.2.12                    3   6   377    19    +40us[ +55us] +/-  200us
^x 192.0.2.14                    5   6   377    12  +125ms[+125ms] +/-    2ms
EOT
EOF
cat > "$W/sources-few" <<'EOF'
#!/bin/sh
cat <<EOT
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^* 192.0.2.11                    2   6   377    20    -10us[ -25us] +/-  110us
^+ 192.0.2.12                    3   6   377    19    +40us[ +55us] +/-  200us
^? 192.0.2.15                    0   6     0     -       +0ns[   +0ns] +/-    0ns
^? 192.0.2.16                    0   6     0     -       +0ns[   +0ns] +/-    0ns
EOT
EOF
cat > "$W/sources-gps" <<'EOF'
#!/bin/sh
cat <<EOT
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
#* GPS                           0   4   377    11    +12us[ +20us] +/-  100us
EOT
EOF
cat > "$W/sources-garbage" <<'EOF'
#!/bin/sh
echo "chronyc: no such command"
EOF
cat > "$W/ntpq-ok" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*192.0.2.20     .GPS.            1 u   45   64  377    0.123   -0.045   0.012
+192.0.2.21     192.0.2.1        2 u   44   64  377    0.234    0.011   0.020
+192.0.2.22     192.0.2.1        2 u   43   64  377    0.198   -0.008   0.015
+192.0.2.23     192.0.2.1        2 u   42   64  377    0.210    0.005   0.018
EOT
EOF
cat > "$W/ntpq-false" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*192.0.2.20     .GPS.            1 u   45   64  377    0.123   -0.045   0.012
+192.0.2.21     192.0.2.1        2 u   44   64  377    0.234    0.011   0.020
+192.0.2.22     192.0.2.1        2 u   43   64  377    0.198   -0.008   0.015
x192.0.2.24     .STEP.          16 u   12   64  377    1.234  +125.3    2.100
EOT
EOF
cat > "$W/ntpq-few" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*192.0.2.20     .GPS.            1 u   45   64  377    0.123   -0.045   0.012
+192.0.2.21     192.0.2.1        2 u   44   64    0    0.234    0.011   0.020
EOT
EOF
cat > "$W/ntpq-gps" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
oGPS_NMEA(0)    .GPS.            0 l    1   16  377    0.000   -0.001   0.002
EOT
EOF
cat > "$W/ntpq-pool" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset   jitter
===============================================================================
 0.debian.pool.n .POOL.          16 p    -  256    0   0.0000   0.0000   0.0001
 1.debian.pool.n .POOL.          16 p    -  256    0   0.0000   0.0000   0.0001
 2.debian.pool.n .POOL.          16 p    -  256    0   0.0000   0.0000   0.0001
 3.debian.pool.n .POOL.          16 p    -   64    0   0.0000   0.0000   0.0001
*51.89.151.183   85.199.214.102   2 u   33   64  377   6.3375  -3.6945   0.0870
+87.106.36.214   193.204.114.233  2 u   31   64  377  11.5186   2.9909   0.1511
EOT
EOF
cat > "$W/ntpq-pool3" <<'EOF'
#!/bin/sh
sh "${0%3}"
echo "+192.0.2.30      192.0.2.1        2 u   30   64  377   0.2100   0.0050   0.0180"
EOF
cat > "$W/ntpq-v6" <<'EOF'
#!/bin/sh
cat <<EOT
     remote           refid      st t when poll reach   delay   offset  jitter
==============================================================================
*fd00:1::10      192.0.2.1        2 u   45   64  377    0.123   -0.045   0.012
EOT
EOF
printf '#!/bin/sh\nexec sleep 30\n' > "$W/ntpq-hung"
# ntpctl -s status, as OpenNTPD's prints it
printf '#!/bin/sh\necho "4/4 peers valid, clock synced, stratum 3"\n' > "$W/ctl-ok"
printf '#!/bin/sh\necho "0/4 peers valid, clock unsynced"\n' > "$W/ctl-unsync"
printf '#!/bin/sh\necho "1/4 peers valid, constraint offset 0s, clock synced, stratum 2"\n' > "$W/ctl-few"
printf '#!/bin/sh\necho "1/1 sensors valid, clock synced, stratum 1"\n' > "$W/ctl-sensor"
printf '#!/bin/sh\necho "ntpctl: connect: /var/run/ntpd.sock: No such file or directory" >&2\nexit 1\n' > "$W/ctl-none"
go() {  # go NAME TIMEDATECTL CHRONYC SOURCES NTPQ [NTPCTL]
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$W/$1'"; echo "Tigris_Timedatectl_Cmd='sh $W/$2'"; echo "Tigris_Chronyc_Cmd='sh $W/$3'"; echo "Tigris_Chronyc_Sources_Cmd='sh $W/$4'"; echo "Tigris_Ntpq_Cmd='sh $W/$5'"; echo "Tigris_Ntpctl_Cmd='sh $W/${6:-ctl-none}'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_timesync ) 2>&1 |
    awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' |
    tr -s ' ' | grep '^--' | grep -v '^--CONFIG--' > "$W/out"
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -c -- "$1" "$W/out"; }

procs tsd systemd-timesyn
go tsd tdc-yes chrony-ok sources-ok ntpq-ok
has '--INFO-- [time003i] The clock is synchronised by systemd-timesyncd.' && [ "`count .`" = 1 ] &&
  ok "systemd-timesyncd (as /proc names it), synchronised: time003i" || { bad "timesyncd"; cat "$W/out"; }
go tsd tdc-no chrony-ok sources-ok ntpq-ok
has '--WARN-- [time002w] systemd-timesyncd is running, but the clock is not synchronised.' && ok "timesyncd not synchronised: time002w" || { bad "timesyncd unsync"; cat "$W/out"; }
procs chr chronyd
go chr tdc-no chrony-ok sources-ok ntpq-ok
has 'The clock is synchronised by chronyd (from ntp.example.org, stratum 3).' && [ "`count time002w`" = 0 ] &&
  ok "chronyd: chronyc decides, not timedatectl (which says no without rtcsync)" || { bad "chrony"; cat "$W/out"; }
go chr tdc-yes chrony-unsync sources-ok ntpq-ok
has '--WARN-- [time002w] chronyd is running, but the clock is not synchronised.' && ok "chronyd not synchronised: time002w" || { bad "chrony unsync"; cat "$W/out"; }
go chr tdc-no chrony-ok sources-false ntpq-ok
has '--WARN-- [time006w] chronyd calls 192.0.2.14 a falseticker' && [ "`count time005w`" = 0 ] &&
  ok "a chrony falseticker: time006w, naming it" || { bad "chrony false"; cat "$W/out"; }
go chr tdc-no chrony-ok sources-few ntpq-ok
has '--WARN-- [time005w] chronyd has only 2 of its 4 time sources answering' &&
  ok "two of four chrony sources answering: time005w" || { bad "chrony few"; cat "$W/out"; }
go chr tdc-no chrony-ok sources-gps ntpq-ok
[ "`count time005w`" = 0 ] && [ "`count time006w`" = 0 ] &&
  ok "a GPS refclock alone: nothing judged" || { bad "chrony gps"; cat "$W/out"; }
go chr tdc-no chrony-ok sources-garbage ntpq-ok
[ "`count time005w`" = 0 ] && [ "`count time006w`" = 0 ] &&
  ok "unparseable sources output: nothing judged" || { bad "chrony garbage"; cat "$W/out"; }
procs ntp ntpd
go ntp tdc-yes chrony-ok sources-ok ntpq-ok
has 'The clock is synchronised by ntpd (stratum 2).' && [ "`count time005w`" = 0 ] && [ "`count time006w`" = 0 ] &&
  ok "ntpd with four peers: stratum 2 in time003i" || { bad "ntpd"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-false
has '--WARN-- [time006w] ntpd calls 192.0.2.24 a falseticker' && [ "`count time005w`" = 0 ] &&
  ok "an ntpd falseticker: time006w, naming it" || { bad "ntpd false"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-few
has '--WARN-- [time005w] ntpd has only 1 of its 2 time sources answering' &&
  ok "one of two ntpd peers answering: time005w" || { bad "ntpd few"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-gps
has 'The clock is synchronised by ntpd (stratum 1).' && [ "`count time005w`" = 0 ] &&
  ok "an ntpd GPS refclock alone: stratum 1, nothing judged" || { bad "ntpd gps"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-pool
has '--WARN-- [time005w] ntpd has only 2 of its 2 time sources answering' &&
  ok "ntpsec's pool rows are not servers: 2 of 2, time005w" || { bad "ntpd pool"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-pool3
[ "`count time005w`" = 0 ] && has 'The clock is synchronised by ntpd (stratum 3).' &&
  ok "three servers drawn from the pools: nothing judged" || { bad "ntpd pool3"; cat "$W/out"; }
go ntp tdc-yes chrony-ok sources-ok ntpq-v6
has '--WARN-- [time005w] ntpd has only 1 of its 1 time source answering' &&
  ok "an IPv6 server starting with a letter is a server, not a clock: time005w" || { bad "ntpd v6"; cat "$W/out"; }
if command -v timeout >/dev/null 2>&1; then
  t0=`date +%s`
  go ntp tdc-yes chrony-ok sources-ok ntpq-hung
  t1=`date +%s`
  [ $((t1 - t0)) -lt 20 ] && has 'The clock is synchronised by ntpd.' && [ "`count time005w`" = 0 ] &&
    ok "a hung ntpq is given up on after five seconds" || { bad "ntpd hung ($((t1 - t0)) s)"; cat "$W/out"; }
fi
# OpenNTPD: its processes are ntpd too. Told apart by their titles
# (ntpd's parent, its ntp engine, its dns engine), or by ntpd.conf
# without ntp.conf; judged by ntpctl -s status, never by ntpq (the
# ntpq given would find too few sources)
title() { printf "$3" > "$W/$1/proc/$2/cmdline"; }
procs ontp ntpd ntpd ntpd
title ontp 2 '/usr/sbin/ntpd\000-s\000'; title ontp 3 'ntpd: ntp engine\000'; title ontp 4 'ntpd: dns engine\000'
go ontp tdc-no chrony-ok sources-ok ntpq-few ctl-ok
has '--INFO-- [time003i] The clock is synchronised by openntpd (stratum 3).' && [ "`count .`" = 1 ] &&
  ok "OpenNTPD by its process titles: ntpctl decides (stratum 3), ntpq not asked" || { bad "openntpd titles"; cat "$W/out"; }
go ontp tdc-yes chrony-ok sources-ok ntpq-few ctl-unsync
has '--WARN-- [time002w] openntpd is running, but the clock is not synchronised.' && has "See 'ntpctl -s peers'" &&
  has '--WARN-- [time005w] openntpd has only 0 of its 4 time sources answering' &&
  ok "OpenNTPD unsynced, no valid peer: time002w and time005w, timedatectl not believed" || { bad "openntpd unsync"; cat "$W/out"; }
go ontp tdc-no chrony-ok sources-ok ntpq-ok ctl-few
has '--WARN-- [time005w] openntpd has only 1 of its 4 time sources answering' && has "'servers' or 'server' lines in ntpd.conf" &&
  has 'synchronised by openntpd (stratum 2).' &&
  ok "OpenNTPD with one valid peer of four, past a constraint: time005w" || { bad "openntpd few"; cat "$W/out"; }
go ontp tdc-no chrony-ok sources-ok ntpq-ok ctl-sensor
[ "`count time005w`" = 0 ] && has 'synchronised by openntpd (stratum 1).' &&
  ok "OpenNTPD on a sensor alone: nothing to outvote" || { bad "openntpd sensor"; cat "$W/out"; }
go ontp tdc-yes chrony-ok sources-ok ntpq-few ctl-none
has 'The clock is synchronised by openntpd.' && [ "`count .`" = 1 ] &&
  ok "ntpctl not answering: timedatectl decides, nothing judged" || { bad "openntpd no ntpctl"; cat "$W/out"; }
procs ontpconf ntpd systemd-timesyn; mkdir -p "$W/ontpconf/etc/openntpd"; : > "$W/ontpconf/etc/openntpd/ntpd.conf"
go ontpconf tdc-yes chrony-ok sources-ok ntpq-few ctl-ok
has 'Running: openntpd systemd-timesyncd.' && [ "`count time005w`" = 0 ] &&
  ok "OpenNTPD by Debian's /etc/openntpd/ntpd.conf, untitled: named in time004w" || { bad "openntpd conf"; cat "$W/out"; }
: > "$W/ontpconf/etc/ntp.conf"
go ontpconf tdc-yes chrony-ok sources-ok ntpq-few ctl-ok
has 'Running: ntpd systemd-timesyncd.' && has '[time005w] ntpd has only 1 of its 2' &&
  ok "an ntp.conf beside it, no title: the reference ntpd, judged by ntpq" || { bad "ntpd conf"; cat "$W/out"; }
procs none sshd cron
go none tdc-yes chrony-ok sources-ok ntpq-ok
has '--WARN-- [time001w] No time synchronisation daemon is running' && [ "`count .`" = 1 ] && ok "no daemon: time001w" || { bad "none"; cat "$W/out"; }
procs two chronyd systemd-timesyn
go two tdc-yes chrony-ok sources-ok ntpq-ok
has '--WARN-- [time004w] More than one time synchronisation daemon is running' && has 'Running: chronyd systemd-timesyncd.' &&
  ok "two daemons: time004w, naming both" || { bad "two"; cat "$W/out"; }
procs ctr; : > "$W/ctr/.dockerenv"
go ctr tdc-yes chrony-ok sources-ok ntpq-ok
[ "`count .`" = 0 ] && ok "a container: nothing said" || { bad "container"; cat "$W/out"; }

[ $fail -eq 0 ] && echo "PASS"
exit $fail
