#!/bin/sh
#
# tests/listening_check.sh - check_listeningprocs against ss, lsof and
# netstat fixtures
#
# Two runs of lsof -F output that differ only in the ports the kernel gave
# out (UDP clients such as browsers and Syncthing hold several, and they
# change every run). The findings must be the same in both, with the ports
# in the detail, so tigris --since does not report them as new each time.
# Fixed ports keep their own finding, loopback and connected sockets are
# left out, and a root listener on every interface is a WARN only, not a
# WARN and an INFO.
#
# Then IPv6, from each of the three tools the check can read: listeners on
# [::] and dual-stack sockets are reported, a process on 0.0.0.0 and on ::
# is one finding, ::1 is loopback, and ss's owner uids become names.
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

# lsof -FpPcnLt: p pid, c command, L login, t type, P protocol, n address
fixture() {  # fixture FILE syncthing-port syncthing-port brave-port root-port
cat > "$1" <<EOF
p1
csshd
Lroot
tIPv4
PTCP
n*:22
p2
csyncthing
Landrei
tIPv4
PUDP
n*:21027
tIPv4
PUDP
n*:$2
tIPv4
PUDP
n*:$3
tIPv4
PTCP
n192.168.1.142:56176->81.150.150.132:443
p3
cbrave
Landrei
tIPv4
PUDP
n192.168.1.142:$4
p4
cnode
Landrei
tIPv4
PTCP
n*:3000
p5
csystemd-resolve
Lsystemd-resolve
tIPv4
PUDP
n127.0.0.53:53
p6
cdhclient
Lroot
tIPv4
PUDP
n*:$5
EOF
}
fixture "$W/a.lsof" 41402 56706 47778 44444
fixture "$W/b.lsof" 37201 58861 39000 33333

mkdir -p "$W/sys/proc/sys/net/ipv4"
printf '32768\t60999\n' > "$W/sys/proc/sys/net/ipv4/ip_local_port_range"

cp "$W/tigerrc" "$W/tigerrc.base"
go() {  # go SETTING JSON-OUT: SETTING names the tool and its fixture
  cp "$W/tigerrc.base" "$W/tigerrc"
  {
    echo "$1"
    echo "Tiger_Sysctl_Root='$W/sys'"
    echo "Tiger_JSON_File='$2'"
    echo "Tiger_Listening_ValidUsers='root'"
    echo "Tiger_Listening_Every=Y"
  } >> "$W/tigerrc"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_listeningprocs ) > "$W/out" 2>&1
}

go "Tiger_LSOF_Cmd='cat $W/a.lsof'" "$W/a.jsonl"
A="$W/a.jsonl"
has() { grep -F -q "$1" "$A"; }

has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  ok "root listener on every interface: lin002i WARN" || bad "sshd lin002i WARN"
[ "`grep -c 'sshd' "$A"`" = 1 ] && ok "and only that, no INFO copy of it" || bad "sshd reported `grep -c sshd "$A"` times"
has '"id":"lin003w","check":"check_listeningprocs","message":"The process `syncthing'"'"' is listening on socket 21027 (UDP on every interface) is run by andrei."' &&
  ok "a fixed port keeps its own finding" || bad "syncthing 21027"
has '"message":"The process `syncthing'"'"' is listening on ephemeral ports (UDP on every interface) is run by andrei.","detail":"Ports 41402, 56706; the kernel gives out 32768-60999, so they change from run to run."' &&
  ok "two ephemeral ports of one process: one finding, the ports in the detail" || bad "syncthing ephemeral"
has '"message":"The process `brave'"'"' is listening on ephemeral ports (UDP on 192.168.1.142 interface) is run by andrei.","detail":"Port 47778;' &&
  ok "one ephemeral port on an address: Port, singular" || bad "brave ephemeral"
has '"message":"The process `node'"'"' is listening on socket 3000 (TCP on every interface) is run by andrei."' &&
  ok "a TCP listener on a fixed port, user process: lin003w with the port" || bad "node 3000"
has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `dhclient'"'"' is listening on ephemeral ports (UDP) on every interface.","detail":"Port 44444;' &&
  ok "a root process on an ephemeral port: lin002i, folded the same way" || bad "dhclient lin002i"
grep -q 'systemd-resolve\|:443\|56176' "$A" && bad "loopback or a connected socket was reported" || ok "loopback and connected sockets are left out"

# The same processes on other ephemeral ports: nothing new, nothing resolved
go "Tiger_LSOF_Cmd='cat $W/b.lsof'" "$W/b.jsonl"
sh "$W/tigris-diff" "$W/a.jsonl" "$W/b.jsonl" > "$W/diff.txt"; st=$?
[ $st -eq 0 ] && grep -q '^  new (0):' "$W/diff.txt" && grep -q '^  resolved (0):' "$W/diff.txt" &&
  ok "two runs that differ only in ephemeral ports compare unchanged" || bad "diff of the two runs: `cat "$W/diff.txt"`"
grep -q '"detail":"Ports 37201, 58861;' "$W/b.jsonl" && ok "the second run's detail has its own ports" || bad "b detail"

# The range comes from the kernel: narrower, and 56706 is a port of its own
printf '40000\t50000\n' > "$W/sys/proc/sys/net/ipv4/ip_local_port_range"
go "Tiger_LSOF_Cmd='cat $W/a.lsof'" "$W/c.jsonl"
grep -F -q 'syncthing'"'"' is listening on ephemeral ports (UDP on every interface) is run by andrei.","detail":"Port 41402; the kernel gives out 40000-50000' "$W/c.jsonl" &&
  grep -F -q 'syncthing'"'"' is listening on socket 56706 (UDP' "$W/c.jsonl" &&
  ok "the range is read from ip_local_port_range" || bad "range from the kernel: `grep syncthing "$W/c.jsonl"`"
printf '32768\t60999\n' > "$W/sys/proc/sys/net/ipv4/ip_local_port_range"

# IPv6 from lsof: type IPv6 records, *:22 next to the IPv4 one, [::1]
cat > "$W/v6.lsof" <<'EOF'
p1
csshd
Lroot
tIPv4
PTCP
n*:22
tIPv6
PTCP
n*:22
p2
csyncthing
Landrei
tIPv6
PTCP
n*:22000
tIPv6
PUDP
n*:43283
tIPv4
PUDP
n*:51780
p3
ccupsd
Lroot
tIPv6
PTCP
n[::1]:631
p4
cnode
Landrei
tIPv6
PTCP
n[::1]:3001
p5
cnginx
Lwww-data
tIPv6
PTCP
n[2001:db8::10]:8443
tIPv6
PTCP
n[2001:db8::10]:8443->[2001:db8::20]:50000
EOF
go "Tiger_LSOF_Cmd='cat $W/v6.lsof'" "$W/v6.jsonl"
A="$W/v6.jsonl"
has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  [ "`grep -c 'sshd' "$A"`" = 1 ] && ok "lsof: sshd on 0.0.0.0 and on :: is one finding" || bad "lsof sshd: `grep sshd "$A"`"
has '"message":"The process `syncthing'"'"' is listening on socket 22000 (TCP on every interface) is run by andrei."' &&
  ok "lsof: a dual-stack listener is reported" || bad "lsof syncthing 22000"
has '"message":"The process `syncthing'"'"' is listening on ephemeral ports (UDP on every interface) is run by andrei.","detail":"Ports 43283, 51780;' &&
  ok "lsof: IPv4 and IPv6 ephemeral ports fold into one finding" || bad "lsof syncthing ephemeral"
has '"level":"INFO","id":"lin002i","check":"check_listeningprocs","message":"The process `cupsd'"'"' is listening on socket 631 (TCP) on loopback interface."' &&
  ok "lsof: [::1] is loopback" || bad "lsof cupsd ::1"
has '"message":"The process `nginx'"'"' is listening on socket 8443 (TCP on 2001:db8::10 interface) is run by www-data."' &&
  ok "lsof: an IPv6 address is kept whole" || bad "lsof nginx 2001:db8::10"
grep -q 'node\|50000' "$A" && bad "lsof: a user process on ::1 or a connected socket was reported" || ok "lsof: ::1 and connected IPv6 sockets are left out"

# ss -Hlntupe, what the check reads when ss is there: the socket owner is
# a uid, left out for root, and several processes can share a socket. The
# user is each process's effective uid from /proc/PID/status when there is
# one (nginx: a root master and two workers), else the socket's owner.
name() { n=`getent passwd "$1" | cut -d: -f1`; echo "${n:-$1}"; }
u1000=`name 1000` u4242=`name 4242421`
for p in 700:0 701:1000 702:1000; do
  mkdir -p "$W/sys/proc/${p%:*}"
  printf 'Name:\tnginx\nUid:\t%s\t%s\t%s\t%s\n' 0 "${p#*:}" "${p#*:}" "${p#*:}" > "$W/sys/proc/${p%:*}/status"
done
cat > "$W/ss.txt" <<'EOF'
tcp LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1239,fd=3),("systemd",pid=1,fd=200)) ino:7871 sk:d cgroup:/system.slice/ssh.socket <->
tcp LISTEN 0 4096 [::]:22 [::]:* users:(("sshd",pid=1239,fd=4),("systemd",pid=1,fd=201)) ino:8654 sk:14 cgroup:/system.slice/ssh.socket v6only:1 <->
tcp LISTEN 0 4096 *:22000 *:* users:(("syncthing",pid=1988,fd=19)) uid:1000 ino:21585 sk:15 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/syncthing.service v6only:0 <->
udp UNCONN 0 0 0.0.0.0:51780 0.0.0.0:* users:(("syncthing",pid=1988,fd=13)) uid:1000 ino:20752 sk:1 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/syncthing.service <->
udp UNCONN 0 0 [::]:43283 [::]:* users:(("syncthing",pid=1988,fd=27)) uid:1000 ino:20764 sk:b cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/syncthing.service v6only:1 <->
tcp LISTEN 0 4096 [::1]:631 [::]:* users:(("cupsd",pid=1221,fd=7)) ino:15584 sk:12 cgroup:/system.slice/cups.service v6only:1 <->
tcp LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:* users:(("systemd-resolve",pid=871,fd=15)) uid:991 ino:13792 sk:f cgroup:/system.slice/systemd-resolved.service <->
udp UNCONN 0 0 0.0.0.0%eth0:68 0.0.0.0:* users:(("dhclient",pid=900,fd=6)) ino:3000 sk:20 cgroup:/system.slice/dhclient.service <->
tcp LISTEN 0 64 0.0.0.0:2049 0.0.0.0:* ino:0 sk:21 <->
tcp LISTEN 0 511 [2001:db8::10]:8443 [::]:* users:(("nginx",pid=702,fd=6),("nginx",pid=701,fd=6),("nginx",pid=700,fd=6)) ino:4000 sk:22 cgroup:/system.slice/nginx.service v6only:1 <->
tcp LISTEN 0 128 *:5000 *:* users:(("Web Content",pid=950,fd=40)) uid:1000 ino:5000 sk:23 cgroup:/user.slice/user-1000.slice/session-c1.scope v6only:0 <->
tcp LISTEN 0 128 0.0.0.0:7000 0.0.0.0:* users:(("ghost",pid=951,fd=3)) uid:4242421 ino:5001 sk:24 cgroup:/system.slice/ghost.service <->
EOF
go "Tiger_SS_Cmd='cat $W/ss.txt'" "$W/ss.jsonl"
A="$W/ss.jsonl"
has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  [ "`grep -c 'sshd' "$A"`" = 1 ] && ok "ss: sshd on 0.0.0.0 and on :: is one finding, its owner root" || bad "ss sshd: `grep sshd "$A"`"
has '"message":"The process `systemd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  ok "ss: every process sharing a socket is named, as lsof names them" || bad "ss systemd"
has '"message":"The process `syncthing'"'"' is listening on socket 22000 (TCP on every interface) is run by '"$u1000"'."' &&
  ok "ss: a dual-stack listener, its owner uid as a name ($u1000)" || bad "ss syncthing 22000"
has '"message":"The process `syncthing'"'"' is listening on ephemeral ports (UDP on every interface) is run by '"$u1000"'.","detail":"Ports 43283, 51780;' &&
  ok "ss: IPv4 and IPv6 ephemeral ports fold into one finding" || bad "ss syncthing ephemeral"
has '"level":"INFO","id":"lin002i","check":"check_listeningprocs","message":"The process `cupsd'"'"' is listening on socket 631 (TCP) on loopback interface."' &&
  ok "ss: [::1] is loopback" || bad "ss cupsd ::1"
has '"message":"The process `dhclient'"'"' is listening on socket 68 (UDP) on eth0 interface."' &&
  ok "ss: a socket bound to a device names the device" || bad "ss dhclient eth0"
has '"message":"The process `nginx'"'"' is listening on socket 8443 (TCP on 2001:db8::10 interface) is run by '"$u1000"'."' &&
  has '"level":"INFO","id":"lin002i","check":"check_listeningprocs","message":"The process `nginx'"'"' is listening on socket 8443 (TCP) on 2001:db8::10 interface."' &&
  [ "`grep -c 'nginx' "$A"`" = 2 ] && ok "ss: an IPv6 address kept whole; the root master and its two workers (euid $u1000) are two findings" || bad "ss nginx: `grep nginx "$A"`"
has '"message":"The process `Web Content'"'"' is listening on socket 5000 (TCP on every interface) is run by '"$u1000"'."' &&
  ok "ss: a process name with a space" || bad "ss Web Content"
has '"message":"The process `ghost'"'"' is listening on socket 7000 (TCP on every interface) is run by '"$u4242"'."' &&
  ok "ss: a uid with no name stays a number" || bad "ss ghost"
grep -q 'systemd-resolve\|2049' "$A" && bad "ss: 127.0.0.53%lo or a socket with no process was reported" || ok "ss: loopback with a zone, and kernel sockets, are left out"

# netstat, the last resort: tcp6 and udp6 lines, raw sockets left out
cat > "$W/netstat.txt" <<'EOF'
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       User       Inode      PID/Program name
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      root       7871       1239/sshd
tcp6       0      0 :::22                   :::*                    LISTEN      root       8654       1239/sshd
tcp6       0      0 ::1:631                 :::*                    LISTEN      root       15584      1221/cupsd
tcp6       0      0 :::22000                :::*                    LISTEN      andrei     21585      1988/syncthing
udp6       0      0 :::21027                :::*                                andrei     20753      1988/syncthing
raw6       0      0 :::58                   :::*                    7           root       23567      994/NetworkManager
EOF
go "Tiger_Netstat_Cmd='cat $W/netstat.txt'" "$W/ns.jsonl"
A="$W/ns.jsonl"
has '"id":"lin004i"' && ok "netstat: says it is the fallback (lin004i)" || bad "netstat lin004i"
has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  [ "`grep -c 'sshd' "$A"`" = 1 ] && ok "netstat: :::22 is every interface, one finding with 0.0.0.0:22" || bad "netstat sshd: `grep sshd "$A"`"
has '"message":"The process `cupsd'"'"' is listening on socket 631 (TCP) on loopback interface."' &&
  ok "netstat: ::1:631 is loopback on port 631" || bad "netstat cupsd"
has '"message":"The process `syncthing'"'"' is listening on socket 22000 (TCP on every interface) is run by andrei."' &&
  has '"message":"The process `syncthing'"'"' is listening on socket 21027 (UDP on every interface) is run by andrei."' &&
  ok "netstat: tcp6 and udp6 listeners" || bad "netstat syncthing"
grep -q 'NetworkManager' "$A" && bad "netstat: a raw socket was reported" || ok "netstat: raw sockets are left out"

# /proc itself, the last resort (Alpine without iproute2 has only busybox's
# lsof and netstat): the kernel's tables as Hera has them, and fd links
# from the processes to their sockets' inodes
P="$W/sys/proc"; mkdir -p "$P/net"
cat > "$P/net/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 7871 1 0000000000000000 100 0 0 10 0
   1: 0100007F:0277 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 15585 1 0000000000000000 100 0 0 10 0
   2: 8E01A8C0:DB30 84969651:01BB 01 00000000:00000000 00:00000000 00000000  1000        0 99001 1 0000000000000000 100 0 0 10 0
EOF
cat > "$P/net/tcp6" <<'EOF'
  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000000000000:0016 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 8654 1 0000000000000000 100 0 0 10 0
   1: 00000000000000000000000001000000:0277 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 15584 1 0000000000000000 100 0 0 10 0
EOF
cat > "$P/net/udp" <<'EOF'
   sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode ref pointer drops
 7397: 00000000:CA44 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 20752 2 0000000000000000 0
 9412: 00000000:5223 00000000:0000 07 00000000:00000000 00:00000000 00000000  1000        0 14323 2 0000000000000000 0
EOF
: > "$P/net/udp6"
proc() {  # proc PID COMM EUID INODE...
  pid=$1 comm=$2 uid=$3; shift 3; mkdir -p "$P/$pid/fd"
  echo "$comm" > "$P/$pid/comm"; printf 'Name:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "$comm" "$uid" "$uid" "$uid" "$uid" > "$P/$pid/status"
  n=3; for i; do ln -s "socket:[$i]" "$P/$pid/fd/$n"; n=$((n + 1)); done
}
proc 1239 sshd 0 7871 8654
proc 1221 cupsd 0 15585 15584
proc 1988 syncthing 1000 20752 14323 99001
go "Tiger_Listening_Source=proc" "$W/proc.jsonl"
A="$W/proc.jsonl"
has '"level":"WARN","id":"lin002i","check":"check_listeningprocs","message":"The process `sshd'"'"' is listening on socket 22 (TCP) on every interface."' &&
  [ "`grep -c 'sshd' "$A"`" = 1 ] && ok "/proc: sshd on 0.0.0.0 and on :: (hex, little-endian) is one finding" || { bad "proc sshd: `grep sshd "$A"`"; }
has '"message":"The process `cupsd'"'"' is listening on socket 631 (TCP) on loopback interface."' && [ "`grep -c cupsd "$A"`" = 1 ] &&
  ok "/proc: 127.0.0.1 and ::1 are loopback" || bad "proc cupsd: `grep cupsd "$A"`"
has '"message":"The process `syncthing'"'"' is listening on socket 21027 (UDP on every interface) is run by '"`name 1000`"'."' &&
  has '"message":"The process `syncthing'"'"' is listening on ephemeral ports (UDP on every interface) is run by '"`name 1000`"'.","detail":"Port 51780;' &&
  ok "/proc: unconnected UDP sockets, the owner from the process's euid" || bad "proc syncthing: `grep syncthing "$A"`"
grep -q '56112\|443' "$A" && bad "/proc: a connected TCP socket was reported" || ok "/proc: a connected TCP socket (state 01) is left out"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- out"; cat "$W/out"; echo "--- a.jsonl"; cat "$W/a.jsonl"; }
exit $fail
