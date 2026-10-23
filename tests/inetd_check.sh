#!/bin/sh
#
# tests/inetd_check.sh - Linux check_inetd on roots
#
# Offline roots (TIGRIS_ROOT): nothing of the kind installed (silent);
# a telnet server installed and nothing enabling it, beside a telnet
# client that is not judged (inet006w); Fedora-style telnet.socket and
# tftp.socket enabled with an rsh server merely installed (inet005f
# twice, inet006w once); xinetd enabled serving telnet, rsync and echo
# with tftp disabled (inet005f, inet006w, inet007w, inet008i); Debian's
# openbsd-inetd enabled through an rc link with telnet commented
# "#<off>#" and shell active (inet005f for rsh, nothing for telnet);
# xinetd installed but not enabled with telnet on in xinetd.d (inet006w
# naming the dormant entry, inet008i, no inet005f); a removed package's
# dangling alternatives link (silent). Live (Tigris_Sysctl_Root): a
# running in.tftpd, found by its process name. Runs as a user and as
# root; the fixtures read the same for both.
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
  tr -s ' ' | grep '^--' | grep -v '^--CONFIG--'
}
run() {  # run ROOT: check_inetd with ROOT as the audited (offline) system
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W TIGRIS_ROOT="$1" sh ./systems/Linux/2/check_inetd ) 2>&1 | join > "$W/out" || true
}
live() {  # live ROOT: the same, live, with /proc and the files under ROOT
  cp "$W/tigris.conf.base" "$W/tigris.conf"
  { echo "Tigris_Sysctl_Root='$1'"; echo "Tigris_Show_INFO_Msgs=Y"; } >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh ./systems/Linux/2/check_inetd ) 2>&1 | join > "$W/out" || true
}
has()   { grep -F -q -- "$1" "$W/out"; }
count() { grep -F -c -- "$1" "$W/out"; }
prog() { mkdir -p "${1%/*}"; printf '\177ELF\n' > "$1"; chmod 755 "$1"; }   # prog PATH
want() { mkdir -p "$1/etc/systemd/system/$2"; ln -s "/usr/lib/systemd/system/$3" "$1/etc/systemd/system/$2/$3"; }  # want ROOT WANTS UNIT

E=$W/empty; mkdir -p "$E/etc" "$E/usr/sbin"
prog "$E/usr/bin/telnet"; prog "$E/usr/bin/tftp"; prog "$E/usr/sbin/sshd"
run "$E"
[ -s "$W/out" ] && { bad "empty"; cat "$W/out"; } || ok "no server, a telnet and a tftp client: nothing said"

I=$W/installed; mkdir -p "$I/etc"
prog "$I/usr/sbin/in.telnetd"; prog "$I/usr/bin/telnet"
run "$I"
has '--WARN-- [inet006w] A telnet server is installed, though not enabled' && has '/usr/sbin/in.telnetd is installed.' &&
[ "`count inet005f`" = 0 ] && [ "`count --`" = 1 ] &&
  ok "in.telnetd installed, nothing enabling it: inet006w, naming the program; the client is not judged" || { bad "installed"; cat "$W/out"; }

F=$W/fedora; mkdir -p "$F/etc"
prog "$F/usr/sbin/in.telnetd"; prog "$F/usr/sbin/in.tftpd"; prog "$F/usr/sbin/in.rshd"; prog "$F/usr/sbin/in.rlogind"
want "$F" sockets.target.wants telnet.socket
want "$F" sockets.target.wants tftp.socket
want "$F" multi-user.target.wants sshd.service
run "$F"
has '--FAIL-- [inet005f] A telnet server is enabled: logins' && has 'telnet.socket is enabled.' &&
has '--FAIL-- [inet005f] A TFTP server is enabled' && has 'tftp.socket is enabled.' && [ "`count inet005f`" = 2 ] &&
  ok "telnet.socket and tftp.socket enabled: inet005f each, naming the unit" || { bad "fedora fail"; cat "$W/out"; }
has '--WARN-- [inet006w] A rsh server is installed, though not enabled' && has '/usr/sbin/in.rshd is installed.' && [ "`count inet006w`" = 1 ] &&
  ok "rsh-server installed, rsh.socket not enabled: inet006w" || { bad "fedora warn"; cat "$W/out"; }

X=$W/xinetd; mkdir -p "$X/etc/xinetd.d"
prog "$X/usr/sbin/xinetd"; prog "$X/usr/sbin/in.telnetd"; prog "$X/usr/sbin/in.tftpd"
want "$X" multi-user.target.wants xinetd.service
cat > "$X/etc/xinetd.conf" <<'EOF'
# Simple configuration file for xinetd
defaults
{
	log_type	= SYSLOG daemon info
	disabled	= daytime
}
includedir /etc/xinetd.d
EOF
printf 'service telnet\n{\n\tdisable\t= no\n\tsocket_type\t= stream\n\tserver\t= /usr/sbin/in.telnetd\n}\n' > "$X/etc/xinetd.d/telnet"
printf 'service tftp\n{\n\tdisable\t= yes\n\tsocket_type\t= dgram\n\tserver\t= /usr/sbin/in.tftpd\n}\n' > "$X/etc/xinetd.d/tftp"
printf 'service rsync\n{\n\tsocket_type\t= stream\n\tserver\t= /usr/bin/rsync\n}\n' > "$X/etc/xinetd.d/rsync"
printf '# default: off\nservice echo\n{\n\tdisable\t= no\n\tid\t= echo-dgram\n\ttype\t= INTERNAL UNLISTED\n\tsocket_type\t= dgram\n}\n' > "$X/etc/xinetd.d/echo-dgram"
printf 'service daytime\n{\n\tdisable\t= no\n\ttype\t= INTERNAL\n\tsocket_type\t= stream\n}\n' > "$X/etc/xinetd.d/daytime"
run "$X"
has '--FAIL-- [inet005f] A telnet server is enabled' && has 'xinetd serves telnet (not disabled in /etc/xinetd.d, xinetd enabled).' && [ "`count inet005f`" = 1 ] &&
  ok "xinetd enabled, xinetd.d/telnet disable = no: inet005f, saying so" || { bad "xinetd telnet"; cat "$W/out"; }
has '--WARN-- [inet006w] A TFTP server is installed, though not enabled' && [ "`count inet006w`" = 1 ] &&
  ok "xinetd.d/tftp disable = yes: the installed in.tftpd is inet006w, not inet005f" || { bad "xinetd tftp"; cat "$W/out"; }
has '--WARN-- [inet007w] The super-server offers the small internal services' && has 'xinetd serves echo' && [ "`count 'serves daytime'`" = 0 ] &&
  ok "echo on in xinetd.d: inet007w; daytime, disabled by the defaults block, is not" || { bad "xinetd small"; cat "$W/out"; }
has '--INFO-- [inet008i] xinetd is enabled, serving: echo, rsync, telnet.' && has '/usr/sbin/xinetd.' &&
  ok "inet008i: xinetd enabled, its services listed (a block without disable is on)" || { bad "xinetd info"; cat "$W/out"; }

D=$W/debian; mkdir -p "$D/etc/rc2.d"
prog "$D/usr/sbin/inetd"; prog "$D/usr/sbin/in.rshd"; prog "$D/usr/sbin/tcpd"
ln -s ../init.d/openbsd-inetd "$D/etc/rc2.d/S01openbsd-inetd"
cat > "$D/etc/inetd.conf" <<'EOF'
# /etc/inetd.conf:  see inetd(8) for further informations.
#:INTERNAL: Internal services
#discard		stream	tcp	nowait	root	internal
#<off># telnet		stream	tcp	nowait	root	/usr/sbin/tcpd	/usr/sbin/in.telnetd
shell		stream	tcp	nowait	root	/usr/sbin/tcpd	/usr/sbin/in.rshd
127.0.0.1:daytime	stream	tcp	nowait	root	internal
EOF
run "$D"
has '--FAIL-- [inet005f] A rsh server is enabled' && has '/etc/inetd.conf serves shell (inetd enabled).' && [ "`count inet005f`" = 1 ] &&
[ "`count telnet`" = 0 ] &&
  ok "openbsd-inetd through an rc link, shell active: inet005f; the #<off># telnet line is a comment" || { bad "debian"; cat "$W/out"; }
has '--WARN-- [inet007w]' && has '/etc/inetd.conf serves daytime (inetd enabled).' &&
  ok "an internal daytime line with a host prefix: inet007w" || { bad "debian daytime"; cat "$W/out"; }
has '--INFO-- [inet008i] inetd is enabled, serving: daytime, shell.' &&
  ok "inet008i: inetd enabled, its services listed" || { bad "debian info"; cat "$W/out"; }

O=$W/dormant; mkdir -p "$O/etc/xinetd.d"
prog "$O/usr/sbin/xinetd"; prog "$O/usr/sbin/in.telnetd"
printf 'service telnet\n{\n\tdisable\t= no\n\tserver\t= /usr/sbin/in.telnetd\n}\n' > "$O/etc/xinetd.d/telnet"
run "$O"
has '--WARN-- [inet006w] A telnet server is installed, though not enabled' && has '/etc/xinetd.d enables telnet, but xinetd is not enabled' &&
[ "`count inet005f`" = 0 ] && [ "`count inet007w`" = 0 ] &&
  ok "xinetd installed but not enabled: the telnet entry is dormant, inet006w names it, no inet005f" || { bad "dormant"; cat "$W/out"; }
has '--INFO-- [inet008i] xinetd is installed but not enabled.' && has 'Its configuration enables: telnet.' &&
  ok "inet008i: xinetd not enabled, what its configuration would serve" || { bad "dormant info"; cat "$W/out"; }

# what update-alternatives leaves when the package behind the link is gone
R=$W/removed; mkdir -p "$R/etc/alternatives" "$R/usr/sbin"
ln -s /etc/alternatives/telnetd "$R/usr/sbin/telnetd"
ln -s /usr/sbin/inetutils-telnetd "$R/etc/alternatives/telnetd"
run "$R"
[ -s "$W/out" ] && { bad "removed"; cat "$W/out"; } || ok "a dangling alternatives link to a removed telnetd: nothing said"

# live: a running in.tftpd (tftpd-hpa started by hand), no unit enabled
L=$W/live; mkdir -p "$L/proc/1" "$L/proc/2" "$L/etc"
prog "$L/usr/sbin/in.tftpd"
echo systemd > "$L/proc/1/comm"; echo in.tftpd > "$L/proc/2/comm"
live "$L"
has '--FAIL-- [inet005f] A TFTP server is enabled' && has 'in.tftpd is running.' && [ "`count inet006w`" = 0 ] &&
  ok "live: in.tftpd running, nothing enabled: inet005f by its process" || { bad "live"; cat "$W/out"; }
echo sshd > "$L/proc/2/comm"
live "$L"
has '--WARN-- [inet006w] A TFTP server is installed, though not enabled' && [ "`count inet005f`" = 0 ] &&
  ok "live: in.tftpd present, not running: inet006w" || { bad "live stopped"; cat "$W/out"; }
grep -q "$W" "$W/out" && bad "a finding names where the root is on this host" || ok "findings name the root's own paths"

[ $fail -eq 0 ] && echo "PASS"
exit $fail
