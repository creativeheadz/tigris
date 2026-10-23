#!/bin/sh
#
# tests/ssh_check.sh - check_ssh against canned sshd -T output
#
# Feeds the check a fixture in which every setting is wrong, then one in
# which every setting is right, through Tigris_SSHD_Cmd; then the edge
# cases: LoginGraceTime 0, a DEBUG LogLevel, a client-alive count of 0,
# DisableForwarding yes over forwarding options left on. Then offline
# roots (TIGRIS_ROOT, as tigris --root sets it), where sshd is not run and
# the configuration is worked out from the files: a Debian-like one whose
# Include file sets PasswordAuthentication before the main file does (the
# first value wins), Keyword=value, the old ChallengeResponseAuthentication
# name, LoginGraceTime in minutes, a Match block whose settings must not
# count, an included file that is an absolute link inside the root, and
# the documented defaults for what is not set; then a root with every
# option written badly and one with every option written well. Needs no
# root and no sshd.
#
TIGER=${TIGER:-`cd "\`dirname "$0"\`/.." && pwd`}
umask 022   # the tree copies and directories made here must be nobody else's to write
W=`mktemp -d`
trap 'rm -rf "$W"' 0
( cd "$TIGER" && tar --exclude=.git --exclude=./log --exclude=./run -cf - . ) | ( cd "$W" && tar -xf - )
mkdir -p "$W/run" "$W/log"
# the INFO findings (the defaults' forwarding and client-alive ones) are
# off in the stock configuration
echo "Tigris_Show_INFO_Msgs=Y" >> "$W/tigris.conf"

cat > "$W/bad.txt" <<FIX
passwordauthentication yes
permitrootlogin yes
permitemptypasswords yes
x11forwarding yes
maxauthtries 6
usepam no
kbdinteractiveauthentication yes
logingracetime 120
hostbasedauthentication yes
ignorerhosts no
permituserenvironment yes
loglevel quiet
allowtcpforwarding yes
allowagentforwarding yes
gatewayports yes
permittunnel yes
maxsessions 20
clientaliveinterval 0
clientalivecountmax 3
strictmodes no
usedns yes
printlastlog no
fingerprinthash md5
disableforwarding no
ciphers aes128-cbc,aes256-ctr,3des-cbc
macs hmac-md5,hmac-sha2-256-etm@openssh.com,hmac-sha1-96
kexalgorithms diffie-hellman-group1-sha1,curve25519-sha256
FIX
cat > "$W/good.txt" <<FIX
passwordauthentication no
permitrootlogin prohibit-password
permitemptypasswords no
x11forwarding no
maxauthtries 4
usepam yes
kbdinteractiveauthentication no
logingracetime 60
hostbasedauthentication no
ignorerhosts yes
permituserenvironment no
loglevel verbose
allowtcpforwarding no
allowagentforwarding no
gatewayports no
permittunnel no
maxsessions 10
clientaliveinterval 15
clientalivecountmax 3
strictmodes yes
usedns no
printlastlog yes
fingerprinthash sha256
disableforwarding no
ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
macs hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
kexalgorithms curve25519-sha256,diffie-hellman-group16-sha512
FIX

run()
{
  echo "Tigris_SSHD_Cmd='cat $1'" >> "$W/tigris.conf"
  ( cd "$W" && TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 )
  sed -i '$d' "$W/tigris.conf"
}
# vary FILE KEY VALUE: a copy of FILE with KEY set to VALUE, printed
vary()
{
  sed "s/^$2 .*/$2 $3/" "$1" > "$W/vary.txt"
  echo "$W/vary.txt"
}

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
run "$W/bad.txt" > "$W/bad.out"
for code in ssh004w ssh006f ssh007f ssh008w ssh009w ssh010w ssh011w ssh012w ssh013w ssh014w ssh015w ssh016w ssh017w ssh018w ssh019w \
            ssh020i ssh021i ssh022i ssh023w ssh024w ssh025w ssh026w ssh027i ssh028i ssh029i
do
  if grep -q "\[$code\]" "$W/bad.out"; then echo "ok   $code reported"; else echo "FAIL $code missing"; fail=1; fi
done
grep -q 'ssh030w' "$W/bad.out" && bad "LogLevel quiet is ssh016w, not the DEBUG finding" || ok "LogLevel quiet is not ssh030w"
grep 'ssh022i' "$W/bad.out" | grep -q 'clientaliveinterval is 0' && ok "ssh022i names the interval" || bad "ssh022i text"
# the weak-algorithm messages must name the weak ones and not the good ones
grep -A1 'ssh017w' "$W/bad.out" | tr -d '\n' | grep -q 'aes128-cbc' && ! grep -A1 'ssh017w' "$W/bad.out" | tr -d '\n' | grep -q 'aes256-ctr' \
  && echo "ok   ssh017w names only the weak cipher" || { echo "FAIL ssh017w cipher list"; fail=1; }

run "$W/good.txt" > "$W/good.out"
if grep -q -- '--\(WARN\|FAIL\|ALERT\|INFO\)--' "$W/good.out"; then
  echo "FAIL good fixture still reported:"; grep -- '--' "$W/good.out" | head; fail=1
else
  echo "ok   nothing reported for the good fixture, not even INFO"
fi

# LoginGraceTime 0 is no limit at all: it must not pass as "under 60"
run "`vary "$W/good.txt" logingracetime 0`" > "$W/zero.out"
grep -q 'ssh012w' "$W/zero.out" && grep -q 'logingracetime is 0:' "$W/zero.out" &&
  echo "ok   LoginGraceTime 0 (no limit) is ssh012w" || { echo "FAIL LoginGraceTime 0 passed"; cat "$W/zero.out"; fail=1; }
# LogLevel: INFO passes (CIS allows INFO or VERBOSE), DEBUG is its own finding
run "`vary "$W/good.txt" loglevel info`" > "$W/info.out"
grep -q 'ssh016w\|ssh030w' "$W/info.out" && { bad "LogLevel INFO was reported"; cat "$W/info.out"; } || ok "LogLevel INFO passes"
run "`vary "$W/good.txt" loglevel debug2`" > "$W/debug.out"
grep -q 'ssh030w' "$W/debug.out" && ! grep -q 'ssh016w' "$W/debug.out" &&
  ok "LogLevel DEBUG2 is ssh030w, not ssh016w" || { bad "LogLevel DEBUG2"; cat "$W/debug.out"; }
# ClientAliveCountMax 0 turns the disconnect off, whatever the interval
run "`vary "$W/good.txt" clientalivecountmax 0`" > "$W/count.out"
grep 'ssh022i' "$W/count.out" | grep -q 'clientalivecountmax is 0' &&
  ok "ClientAliveCountMax 0 with an interval set: ssh022i, naming the count" || { bad "ClientAliveCountMax 0"; cat "$W/count.out"; }
# MaxSessions 11 is one too many; MaxAuthTries 4 is CIS's limit and passes (in good.txt)
run "`vary "$W/good.txt" maxsessions 11`" > "$W/sess.out"
grep -q 'ssh025w' "$W/sess.out" && ok "MaxSessions 11: ssh025w" || { bad "MaxSessions 11"; cat "$W/sess.out"; }
# the forwarding options under DisableForwarding yes are overridden, so not reported
sed 's/^disableforwarding .*/disableforwarding yes/; s/^x11forwarding .*/x11forwarding yes/; s/^allowtcpforwarding .*/allowtcpforwarding yes/
     s/^allowagentforwarding .*/allowagentforwarding yes/; s/^permittunnel .*/permittunnel yes/; s/^gatewayports .*/gatewayports yes/' "$W/good.txt" > "$W/fwd.txt"
run "$W/fwd.txt" > "$W/fwd.out"
grep -q 'ssh008w\|ssh020i\|ssh021i\|ssh023w\|ssh024w' "$W/fwd.out" &&
  { bad "a forwarding option reported under DisableForwarding yes"; cat "$W/fwd.out"; } ||
  ok "DisableForwarding yes: X11, TCP, agent, tunnel and gateway settings are not reported"

# An offline root, as Debian ships it: what is not set takes the defaults
R=$W/img
mkdir -p "$R/etc/ssh/sshd_config.d" "$R/usr/share/ssh"
cat > "$R/etc/ssh/sshd_config" <<'CONF'
# as Debian ships it: the drop-ins first
Include /etc/ssh/sshd_config.d/*.conf
PasswordAuthentication yes
PermitRootLogin=yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
LoginGraceTime 2m
Ciphers aes256-gcm@openssh.com,aes128-cbc
Match User backup
	PermitEmptyPasswords yes
	MaxAuthTries 10
	MaxSessions 50
CONF
echo 'PasswordAuthentication no' > "$R/etc/ssh/sshd_config.d/10-nopass.conf"
# a drop-in that is an absolute link: read inside the root, its LogLevel
# counts; followed on this host it would name nothing
echo 'LogLevel QUIET' > "$R/usr/share/ssh/20-log.conf"
ln -s /usr/share/ssh/20-log.conf "$R/etc/ssh/sshd_config.d/20-log.conf"
echo 'IgnoreRhosts no' > "$R/etc/ssh/sshd_config.d/30-skipped.conf.disabled"
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/root.out"
codes=`grep -o '\[ssh0[0-9][0-9][a-z]\]' "$W/root.out" | sort -u | tr -d '[]' | tr '\n' ' '`
[ "$codes" = "ssh006f ssh008w ssh009w ssh012w ssh016w ssh017w ssh020i ssh021i ssh022i " ] &&
  ok "offline root: root login, X11, the default MaxAuthTries, LoginGraceTime 2m, the linked drop-in's LogLevel, a CBC cipher, and the defaults' forwarding and client-alive INFOs; nothing else" || { bad "offline codes: $codes"; cat "$W/root.out"; }
grep -q 'Checking the sshd configuration written in /etc/ssh/sshd_config and its Include files' "$W/root.out" &&
  ok "offline root: says the configuration was read, not asked of sshd" || bad "offline heading"
grep -q 'logingracetime is 120:' "$W/root.out" && grep -q 'maxauthtries is 6:' "$W/root.out" &&
  ok "offline root: 2m is 120 seconds; the Match block's MaxAuthTries 10 does not count, the default 6 does" || { bad "offline values"; cat "$W/root.out"; }
grep -q 'clientaliveinterval is 0' "$W/root.out" && ! grep -q 'maxsessions' "$W/root.out" &&
  ok "offline root: the defaults ClientAliveInterval 0 and MaxSessions 10 apply, the Match block's MaxSessions 50 does not" || { bad "offline defaults"; cat "$W/root.out"; }

# A root with every option written badly, and one with every option well
B=$W/badroot; mkdir -p "$B/etc/ssh" "$B/etc/pam.d"; : > "$B/etc/pam.d/sshd"
cat > "$B/etc/ssh/sshd_config" <<'CONF'
PasswordAuthentication yes
PermitRootLogin yes
PermitEmptyPasswords yes
X11Forwarding yes
MaxAuthTries 6
UsePAM no
KbdInteractiveAuthentication yes
LoginGraceTime 2m
HostbasedAuthentication yes
IgnoreRhosts no
PermitUserEnvironment yes
LogLevel DEBUG
AllowTcpForwarding local
AllowAgentForwarding yes
GatewayPorts clientspecified
PermitTunnel point-to-point
MaxSessions 20
ClientAliveInterval 0
StrictModes no
UseDNS yes
PrintLastLog no
FingerprintHash MD5
CONF
( cd "$W" && TIGRIS_ROOT=$B TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/badroot.out"
for code in ssh004w ssh006f ssh007f ssh008w ssh009w ssh010w ssh011w ssh012w ssh013w ssh014w ssh015w ssh030w \
            ssh020i ssh021i ssh022i ssh023w ssh024w ssh025w ssh026w ssh027i ssh028i ssh029i
do
  grep -q "\[$code\]" "$W/badroot.out" || { bad "offline, every option bad: $code missing"; }
done
grep -q 'ssh016w' "$W/badroot.out" && bad "offline: LogLevel DEBUG gave ssh016w" || ok "offline, every option written badly: each reported, DEBUG as ssh030w"
G=$W/goodroot; mkdir -p "$G/etc/ssh" "$G/etc/pam.d"; : > "$G/etc/pam.d/sshd"
cat > "$G/etc/ssh/sshd_config" <<'CONF'
PasswordAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 4
UsePAM yes
KbdInteractiveAuthentication no
LoginGraceTime 1m
HostbasedAuthentication no
IgnoreRhosts yes
PermitUserEnvironment no
LogLevel VERBOSE
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
MaxSessions 10
ClientAliveInterval 5m
ClientAliveCountMax 3
StrictModes yes
UseDNS no
PrintLastLog yes
FingerprintHash SHA256
CONF
( cd "$W" && TIGRIS_ROOT=$G TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/goodroot.out"
grep -q -- '--\(WARN\|FAIL\|ALERT\|INFO\)--' "$W/goodroot.out" &&
  { bad "offline, every option good: something reported"; cat "$W/goodroot.out"; } ||
  ok "offline, every option written well (ClientAliveInterval 5m, SHA256): nothing reported"

rm "$R/etc/ssh/sshd_config" "$R/etc/ssh/sshd_config.d"/*
( cd "$W" && TIGRIS_ROOT=$R TIGERHOMEDIR=$W sh scripts/check_ssh 2>&1 ) > "$W/none.out"
grep -q -- '--\(WARN\|FAIL\|INFO\)--' "$W/none.out" && bad "a root without sshd_config: findings" || ok "a root without sshd_config: nothing to say"

[ $fail -eq 0 ] && echo "PASS" || { echo "--- bad.out"; cat "$W/bad.out"; }
exit $fail
