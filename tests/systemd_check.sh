#!/bin/sh
#
# tests/systemd_check.sh - check_systemd against canned ss and
# systemd-analyze output
#
# Feeds the check a fixture through Tigris_SS_Cmd and
# Tigris_Systemd_Analyze_Cmd: three listening units, one UNSAFE, one
# EXPOSED, one OK, plus a socket-activated one, a user service and a
# session scope that must be ignored. Needs no root and no systemd.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"

cat > "$W/ss.txt" <<'FIX'
tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3)) uid:0 ino:1 sk:1 cgroup:/system.slice/ssh.socket <->
tcp LISTEN 0 128 0.0.0.0:631 0.0.0.0:* users:(("cupsd",pid=2,fd=7)) uid:0 ino:2 sk:2 cgroup:/system.slice/cups.service <->
udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:* users:(("avahi",pid=3,fd=12)) uid:111 ino:3 sk:3 cgroup:/system.slice/avahi-daemon.service <->
tcp LISTEN 0 128 127.0.0.53%lo:53 0.0.0.0:* users:(("resolved",pid=4,fd=14)) uid:991 ino:4 sk:4 cgroup:/system.slice/systemd-resolved.service <->
udp UNCONN 0 0 0.0.0.0:21027 0.0.0.0:* users:(("syncthing",pid=5,fd=30)) uid:1000 ino:5 sk:5 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/syncthing.service <->
udp UNCONN 0 0 224.0.0.251:5353 0.0.0.0:* users:(("brave",pid=6,fd=1)) uid:1000 ino:6 sk:6 cgroup:/user.slice/user-1000.slice/session-c1.scope <->
FIX

cat > "$W/analyze.sh" <<'FIX'
#!/bin/sh
# no argument: the overview; a unit: its table, as printed under LC_ALL=C
if [ $# -eq 0 ]; then
cat <<EOT
UNIT                                  EXPOSURE PREDICATE HAPPY
ModemManager.service                       6.3 MEDIUM    x
ssh.service                                9.6 UNSAFE    x
cups.service                               9.2 UNSAFE    x
avahi-daemon.service                       7.8 EXPOSED   x
systemd-resolved.service                   2.1 OK        x
alsa-state.service                         9.6 UNSAFE    x
EOT
else
cat <<EOT
  NAME                                   DESCRIPTION                                   EXPOSURE
- PrivateNetwork=                        Service has access to the host's network                0.5
- RestrictAddressFamilies=~AF_(INET|INET6) Service may allocate Internet sockets                0.3
- RootDirectory=/RootImage=              Service runs within the host's root directory      0.1
- User=/DynamicUser=                     Service runs as root user                          0.4
- NoNewPrivileges=                       Service processes may acquire new privileges       0.3
+ AmbientCapabilities=                   Service process does not receive ambient capabilities
- PrivateTmp=                            Service has access to other software's temporary files 0.1
- ProtectSystem=                         Service has full access to the OS file hierarchy   0.2
- CapabilityBoundingSet=~CAP_BPF         Service may not load BPF programs

→ Overall exposure level for $1: 9.6 UNSAFE
EOT
fi
FIX
chmod +x "$W/analyze.sh"

{
  echo "Tigris_SS_Cmd='cat $W/ss.txt'"
  echo "Tigris_Systemd_Analyze_Cmd='sh $W/analyze.sh'"
  echo "Tigris_Show_INFO_Msgs=Y"
} >> "$W/tigris.conf"
( cd "$W" && TIGERHOMEDIR=$W sh systems/Linux/2/check_systemd 2>&1 ) > "$W/out"
# join wrapped lines
awk '/^--/ { if (l != "") print l; l = $0; next } /^ / { sub(/^ +/, " "); l = l $0; next } { if (l != "") print l; l = "" } END { if (l != "") print l }' "$W/out" | tr -s ' ' > "$W/joined"

fail=0
check() { if grep -q "$1" "$W/joined"; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi; }
nocheck() { if grep -q "$1" "$W/joined"; then echo "FAIL $2"; fail=1; else echo "ok   $2"; fi; }
check 'sysd001w.*ssh.service listens on 22/tcp with exposure 9.6 (UNSAFE)'   "socket-activated ssh scored as its service, UNSAFE"
check 'sysd001w.*ssh.service.*User=/DynamicUser=, NoNewPrivileges=, ProtectSystem='   "the three heaviest missing protections named, by weight"
nocheck 'PrivateNetwork\|RestrictAddressFamilies'                               "network-isolating options are not suggested to a listener"
check 'sysd001w.*cups.service listens on 631/tcp'                              "cups reported UNSAFE"
check 'sysd002i.*avahi-daemon.service listens on 5353/udp with exposure 7.8'   "avahi reported EXPOSED as INFO"
nocheck 'systemd-resolved'                                                     "an OK unit is not reported"
nocheck 'syncthing\|session-c1'                                                "user services and session scopes are ignored"
check 'sysd003i.*3 of 6 system services UNSAFE and 1 EXPOSED'                  "summary counts"
[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/joined"; }
exit $fail
